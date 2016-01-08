from multicorn import ForeignDataWrapper
import os
import stat
from time import ctime
from grp import getgrgid
from pwd import getpwuid

class FilesystemForeignDataWrapper(ForeignDataWrapper):
    def __init__(self, options, columns):
        self.col_map={
            'permissions': 'st_mode',
            'links': 'st_nlink',
            'owner': 'st_uid',
            'group': 'st_gid',
            'size': 'st_size',
            'last_mod': 'st_mtime' }
        super(FilesystemForeignDataWrapper, self).__init__(options, columns)
        self.columns = columns

    def execute(self, quals, columns):
        path = None
        for qual in quals:
            if (qual.field_name == 'path' or qual.field_name == 'id') and qual.operator == '=':
                path = qual.value

        if path is None:
            yield {}
            return

        for filename in os.listdir(path):
            f=os.stat(path + '/' + filename)
            row={}
            for column_name in columns:
                if column_name == 'id' or column_name == 'path':
                    row[column_name] = path #+ '/' + filename
                elif column_name == 'name':
                    row[column_name] = filename
                elif column_name == 'content':
                    row[column_name] = 'content'

                elif column_name == 'parent_id' or column_name == 'directory_id':
                    if path == '/':
                        row[column_name] = None
                    else:
                        row[column_name] = '/'.join( path.split('/')[:-1] )

                elif column_name == 'group':
                    row[column_name] = getgrgid( getattr(f, self.col_map[column_name]) ).gr_name
                elif column_name == 'owner':
                    row[column_name] = getpwuid( getattr(f, self.col_map[column_name]) ).pw_name
                elif column_name == 'permissions':
                    row[column_name] = oct( stat.S_IMODE( getattr(f, self.col_map[column_name]) ) )
                elif column_name == 'last_mod':
                    row[column_name] = ctime( getattr(f, self.col_map[column_name]) )

                elif column_name in self.col_map:
                        row[column_name] = getattr(f, self.col_map[column_name])

                else:
                    row[column_name] = None
            yield row
