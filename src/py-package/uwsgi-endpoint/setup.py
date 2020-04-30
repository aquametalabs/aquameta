from setuptools import setup, find_packages


setup(name='aquameta-endpoint',
      author='Aquameta Labs',
      author_email='eric@aquameta.com',
      description='uWSGI service for the Aquameta endpoint',
      include_package_data=True,
      long_description=open('README.md', 'r').read(),
      packages=find_packages(),
      url='https://github.com/aquametalabs/aquameta',
      version='0.2',
      install_requires=['uwsgi', 'Werkzeug==0.16.1', 'psycopg2'],
      classifiers=['Development Status :: 3 - Alpha',
                   'Intended Audience :: Developers',
                   'Operating System :: OS Independent',
                   'Programming Language :: Python',
                   'Topic :: Database'])
