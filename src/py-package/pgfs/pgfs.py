#!/usr/bin/env python2
from fuse import FUSE, FuseOSError, Operations, LoggingMixIn, fuse_get_context
from errno import ENOENT, EROFS
from os.path import normpath
from psycopg2 import connect, ProgrammingError, DataError, InternalError
from psycopg2.extensions import QuotedString
from stat import S_IFDIR, S_IFREG
from sys import exit
from time import time, sleep
import argparse, getpass
import logging

logging.basicConfig()

class PostgresFS(LoggingMixIn, Operations):
    def __init__(self, database, port=5432, host='localhost', username=None, password=None):
        self.database = database
        self.port = port
        self.host = host
        self.username = username
        self.password = password
        if host:
            self.conn = connect(database=database, port=port, host=host, user=username, password=password)
        else:
            self.conn = connect(database=database, port=port, user=username, password=password)
        self.write_buffer = None # Used to hold what we write when flush is called

    def _row_exists(self, schema, table, pk):
        exists = False
        cur = self.conn.cursor()

        try:
            cur.execute("SELECT 1 FROM \"{}\".\"{}\" where id = '{}' LIMIT 1".format(schema, table, pk))
        except DataError:
            cur.close()
            return False;

        result = cur.fetchone()
        exists = True if result else False
        cur.close()
        return exists

    def _schema_exists(self, schema_name):
        exists = False
        cur = self.conn.cursor()
        cur.execute("SELECT 1 FROM meta.schema where name = '{}' LIMIT 1".format(schema_name))
        result = cur.fetchone()
        exists = True if result else False
        cur.close()
        return exists

    def _get_pk_data(self, schema, tablename, pk, col, offset=0, limit=0):
        #print "Updating data"
        if self._schema_exists(schema):
            cur = self.conn.cursor()
            #print "Pulling data for {}.{}.{}.{}, O: {}, L: {}".format(schema, tablename, pk, col, offset, limit)
            try:
                if limit != 0:
                    offset = offset + 1
                    cur.execute("SELECT substring({col}::text from {off} for {lim}) FROM \"{s}\".\"{t}\" where id = '{pk}'".format(s=schema, t=tablename, pk=pk, col=col, off=offset, lim=limit))
                else:
                    cur.execute("SELECT \"{col}\" FROM \"{s}\".\"{t}\" where id = '{pk}'".format(s=schema, t=tablename, pk=pk, col=col))
            except Exception as e:
                #print "LIMIT: {} OFFSET: {} ERROR: {}".format(limit, offset, e)
                self.conn.rollback()
                cur.close()
                raise FuseOSError(ENOENT)
            #print "Cursor status: {}".format(cur.statusmessage)
            data = cur.fetchall()
            cur.close()
            formatted = str(data[0][0]).encode('utf-8', errors='replace')
            return formatted
        raise FuseOSError(ENOENT)
        return None

    def _set_pk_data(self, schema, tablename, pk, col):
        #print "Updating data"
        if self._schema_exists(schema) and self.write_buffer is not None:
            cur = self.conn.cursor()
            try:
                to_write = QuotedString(self.write_buffer).getquoted()
                cur.execute("UPDATE \"{s}\".\"{t}\" SET {col} = {wb} WHERE id = '{pk}'".format(s=schema, wb=to_write, t=tablename, pk=pk, col=col))
                #print "Cursor status: {}".format(cur.statusmessage)
                self.conn.commit()
            except InternalError as e:
                self.conn.rollback()
                return False
            else:
                return True
            finally:
                cur.close()
                self.write_buffer = None
        elif self.write_buffer is not None:
            self.write_buffer = None
            raise FuseOSError(ENOENT)
        return False

    def read(self, path, size, offset, fh):
        #print "Calling read"
        if size == 0L:
            return 0

        split = normpath(path).split("/")

        #print "Reading {}".format(path)
        if len(split) == 5:
            schema = split[1]
            tablename = split[2]
            pk = split[3]
            col = split[4]
            data = self._get_pk_data(schema, tablename, pk, col, offset=offset, limit=long(size))
            return data

        raise FuseOSError(ENOENT)

    def create(self, path, mode, fh=None):
        #print "Create called."
        raise FuseOSError(EROFS)

    def flush(self, path, fh):
        #print "Calling flush"
        split = normpath(path).split("/")
        # We only write rows
        if len(split) == 5 and self.write_buffer:
            schema = split[1]
            tablename = split[2]
            pk = split[3]
            col = split[4]
            self._set_pk_data(schema, tablename, pk, col)
        return 0

    def unlink(self, path):
        #print "Calling unlink"
        split = normpath(path).split("/")
        # We only write rows
        if len(split) == 5:
            return 0
        raise FuseOSError(ENOENT)

    def write(self, path, data, offset, fh):
        #print "Write called"
        if self.write_buffer is None:
            # This is the first write to a file, so we need to get the data for it
            split = normpath(path).split("/")
            # We only write rows
            if len(split) == 5:
                schema = split[1]
                tablename = split[2]
                pk = split[3]
                col = split[4]
                if self._schema_exists(schema) and self._row_exists(schema, tablename, pk):
                    tdata = self._get_pk_data(schema, tablename, pk, col)
                    self.write_buffer = str(tdata).encode('utf-8', errors='replace')
                else:
                    raise FuseOSError(ENOENT)

        # Replace the chunk of the write-buffer with the data we were passed in
        self.write_buffer = self.write_buffer[0:offset] + data
        return len(data)

    def truncate(self, path, length, fh=None):
        #print "Want to truncate: {}".format(length)
        if self.write_buffer is None:
            # This is the first write to a file, so we need to get the data for it
            split = normpath(path).split("/")
            # We only write rows
            if len(split) == 5:
                schema = split[1]
                tablename = split[2]
                pk = split[3]
                col = split[4]
                tdata = self._get_pk_data(schema, tablename, pk, col)
                self.write_buffer = str(tdata).encode('utf-8', errors='replace')
            self.write_buffer = self.write_buffer[:length]
        return 0

    def getattr(self, path, fh=None):
        #print "Calling getattr"
        to_return = None
        uid, gid, pid = fuse_get_context()
        split = normpath(path).split("/")
        if len(split) != 5:
            to_return = {
                'st_atime': time(),
                'st_gid': 0,
                'st_uid': 0,
                'st_mode': S_IFDIR | 0755,
                'st_mtime': 667908000,
                'st_ctime': 667908000,
                'st_size': 4096
            }
        else:
            schema = split[1]
            tablename = split[2]
            pk = split[3]
            col = split[4]
            formatted = self._get_pk_data(schema, tablename, pk, col)
            if formatted is not None:
                to_return = {
                    'st_atime': time(),
                    'st_gid': 0,
                    'st_uid': 0,
                    'st_mode': S_IFREG | 0666,
                    'st_mtime': 667908000,
                    'st_ctime': 667908000,
                    'st_size': len(formatted)
                }
            else:
                raise FuseOSError(ENOENT)
        return to_return

    def readdir(self, path, fh):
        cur = self.conn.cursor()
        to_return = None #['.', '..']

        normalized = normpath(path)
        split = normalized.split("/")
        #print "Reading dir {}".format(path)
        if len(path) == 1:
            all_schemas = cur.execute("SELECT name FROM meta.schema")
            to_return = [x[0] for x in cur.fetchall()]
        elif len(split) == 2 and split[1] != '':
            schema = split[1]
            if self._schema_exists(schema):
                cur.execute("select t.name from meta.table t join meta.schema s on s.id = t.schema_id where s.name = '{schema}';".format(schema=schema))
                to_return = [x[0] for x in cur.fetchall()]
            else:
                raise FuseOSError(ENOENT)
        elif len(split) == 3:
            schema = split[1]
            tablename = split[2]
            if self._schema_exists(schema):
                try:
                    cur.execute("SELECT id FROM \"{}\".\"{}\"".format(schema, tablename))
                except ProgrammingError:
                    self.conn.rollback()
                    cur.close()
                    raise FuseOSError(ENOENT)
                to_return = [str(x[0]) for x in cur.fetchall()]
            else:
                raise FuseOSError(ENOENT)
        elif len(split) == 4:
            schema = split[1]
            tablename = split[2]
            pk = split[3]
            if self._schema_exists(schema) and self._row_exists(schema, tablename, pk):
                query = "SELECT c.name from meta.\"column\" c join meta.relation t on c.relation_id = t.id join meta.\"schema\" s on t.schema_id = s.id where s.name = '{schema}' and t.name = '{tablename}';".format(tablename=tablename, schema=schema)
                cur.execute(query)
                all_cols = cur.fetchall()
                to_return = [str(x[0]) for x in all_cols]
            else:
                raise FuseOSError(ENOENT)
        cur.close()

        if not to_return:
            raise FuseOSError(ENOENT)
        return to_return + ['.', '..']

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Mount a postgresql database with FUSE.")
    parser.add_argument('mount_point', type=str)
    parser.add_argument('--port', dest='port', type=int)
    parser.add_argument('--host', dest='host', type=str)
    parser.add_argument('-d', '--database', dest='database', required=True, type=str)
    parser.add_argument('-u', '--username', dest='username', type=str)
    parser.add_argument('-p', '--password', dest='password', type=str)
    args = parser.parse_args()

    fsthing = PostgresFS(args.database,
            port=args.port if args.port else 5432,
            username=args.username if args.username else getpass.getuser(),
            host=args.host if args.host else None,
            password=args.password if args.password else None
        )
    fuse = FUSE(fsthing, args.mount_point, foreground=True, nothreads=True)
