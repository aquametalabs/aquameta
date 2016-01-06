from . import ForeignDataWrapper
#from multicorn import ForeignDataWrapper
import os

class FilesystemFdw(ForeignDataWrapper):
    def __init__(self, options, columns):
        super(FilesystemFdw, self).__init__(options, columns)
        self.columns = columns

    def execute(self, quals, columns):
        for filename in os.listdir(path):
            f=os.stat(filename)
            row={}
            for column_name in self.columns:
                line[column_name] = f[column_name]
#                yield (
#                    f.st_mode,
#                    f.st_nlink,
#                    f.st_uid,
#                    f.st_gid,
#                    f.st_size,
#                    f.st_mtime,
#                    path + '/' + filename )
            row['path'] = path + '/' + filename
            yield row
