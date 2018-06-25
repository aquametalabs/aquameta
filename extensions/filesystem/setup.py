import subprocess
from setuptools import setup, find_packages, Extension

setup(
  name='filesystem_fdw',
  version='0.2.0',
  author='Eric Hanson',
  license='Postgresql',
  packages=['filesystem_fdw']
)

