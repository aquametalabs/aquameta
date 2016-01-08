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
            for column_name in self.columns:
                if column_name == 'id' or column_name == 'path':
                    row[column_name] = path #+ '/' + filename
                elif column_name == 'name':
                    row[column_name] = filename
                elif column_name == 'content':
                    row[column_name] = 'content'
                elif column_name in self.col_map:
                    row[column_name] = getattr(f, self.col_map[column_name])
                else:
                    row[column_name] = None
            yield row
