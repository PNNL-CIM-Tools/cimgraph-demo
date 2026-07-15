# Base image for the CIM Tools demo.
#
# We use the Ubuntu 24.04 (noble) devcontainer base — NOT the stock python
# image — because GLIMPSE's bundled Python server (a pyinstaller build shipping
# its own libpython3.14.so) is linked against glibc 2.38. Debian 12 "bookworm"
# (what devcontainers/python:1-3.12 is built on) only has glibc 2.36, so the
# GLIMPSE backend fails to load with:
#   libpython3.14.so.1.0: version `GLIBC_2.38' not found
# Ubuntu 24.04 ships glibc 2.39, which satisfies it. CIMTool (its own bundled
# JRE) runs fine on either.
#
# Python itself is added by the `python` devcontainer feature (the base image
# has none), and uv drives the project venv.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04
