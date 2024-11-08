from setuptools import setup, Extension
import shlex
import subprocess


def pkg_config(package, flags):
    proc = subprocess.run(['pkg-config', flags, package], capture_output=True)
    return shlex.split(proc.stdout.decode('utf-8'))


packages = 'gtk+-3.0 pygobject-3.0'
compile_args = ['-I/usr/include/zbar'] + pkg_config(packages, '--cflags')
link_args = ['-lzbargtk'] + pkg_config(packages, '--libs')
module = Extension('zbargtk', ['pyzbargtk.c'], extra_compile_args=compile_args,
                   extra_link_args=link_args)
setup(name='zbargtk', ext_modules=[module])
