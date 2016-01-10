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
	self.type = options['table_name']

    def execute(self, quals, columns):
        path = None

        for qual in quals:
            if (qual.field_name == 'path' or qual.field_name == 'id') and qual.operator == '=':
                path = os.path.abspath(qual.value)
		
		# If path is not supplied, return empty set
		if not os.path.exists(path):
		    yield {}
		    return

		elif path == '/':
	            row=self.get_file_stat(columns, '/')
		    yield row
		    return

	        filename=path.split('/')[-1]
	        path='/' + '/'.join(path.split('/')[1:-1])
		# If its a file -- we want one result path = path, file = filename
		# If its a directory -- we want one result path = parent_id and file = directory

	        row=self.get_file_stat(columns, filename, path)

                # If 'file' table, get content
                if self.type == 'file' and stat.S_ISREG( os.stat(path + '/' + filename).st_mode ) and 'content' in columns:
                    with open(path + '/' + filename, 'r') as infile:
                    # import codecs
                    # with codecs.open(path, 'r', 'ascii') as infile:
                        row['content'] = infile.read().replace('\n', '')
                        #row['content'] = infile.read().decode('utf-8').encode('ascii', 'ignore')

	        yield row


	    elif (qual.field_name == 'directory_id' or qual.field_name == 'parent_id') and qual.operator == '=':
		path = os.path.abspath(qual.value)

		# If path doesn't exist
		if not os.path.exists(path):
		    yield {}

		# If path is a directory
		elif os.path.isdir(path):
		    for filename in os.listdir(path):
			# Get stats for path
			row=self.get_file_stat(columns, filename, path)
			yield row




    def get_file_stat(self, columns, filename, path=None):
	if path is None:
	    fullpath=filename
	elif path == '/':
	    fullpath=path + filename
	else:
	    fullpath=path + '/' + filename
	f=os.stat(fullpath)
	row={}	
        for column_name in columns:
            if column_name == 'id' or column_name == 'path':
                row[column_name] = fullpath
            elif column_name == 'name':
                row[column_name] = filename
            elif column_name == 'content':
	        row[column_name] = u'...'

            elif column_name == 'parent_id' or column_name == 'directory_id':
                row[column_name] = path
	        #if path == '/' or path == '':
		#    # Root directory has no parent
	    	#    row[column_name] = None
	        #else:
                #    row[column_name] = path
                #    #row[column_name] = '/' + '/'.join( path.split('/')[1:-1] )

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

        return row

