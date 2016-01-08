from multicorn import ForeignDataWrapper
import os

class FilesystemForeignDataWrapper(ForeignDataWrapper):
    def __init__(self, options, columns):
        self.col_map={
            'permissions': 'st_mode',
            'link': 'st_nlink:',
            'user': 'st_uid',
            'group': 'st_gid',
            'size': 'st_size',
            'last_mod': 'st_mtime' }
        super(FilesystemForeignDataWrapper, self).__init__(options, columns)
        self.columns = columns

    def execute(self, quals, columns):
        for qual in quals:
            if (qual.field_name == 'path' or qual.field_name == 'id') and qual.operator == '=':
                path = qual.value

	if path is null:
	    yield {}

        for filename in os.listdir(path):
            f=os.stat(filename)
            row={}
            for column_name in self.columns:
                if column_name == 'id' or column_name == 'path':
                    row[column_name] = path #+ '/' + filename
                if column_name == 'content':
                    row[column_name] = 'content'
                row[column_name] = f[ self.col_map[column_name] ]
            yield row
