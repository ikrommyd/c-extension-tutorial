#!/bin/bash
```
(
    set -e

    # build a debug version of CPython
    pushd submodules/cpython

    if [ `uname` = "Linux" ];then
        BUILD_DEP=''
        INSTALL=''
        if command -v pacman;then
            INSTALL='pacman -S --noconfirm xz'
        elif command -v dnf; then
            BUILD_DEP='dnf builddep -y'
            INSTALL='dnf install -y'
        elif command -v apt-get;then
            BUILD_DEP='apt-get build-dep --assume-yes'
            INSTALL='apt-get install --assume-yes'
        fi

        if [ -n "$BUILD_DEP" ];then
            echo "running: sudo $BUILD_DEP python3"
            sudo $BUILD_DEP python3
        fi

        if [ -n "$INSTALL" ];then
            echo "running: sudo $INSTALL gdb"
            sudo $INSTALL gdb
        fi

        PYTHON_EXE=python
        ./configure --with-pydebug
    elif [ `uname` = "Darwin" ];then
        # install some required packages
        brew install openssl xz

        # Get Python version from the source tree
        PYTHON_VERSION=$(grep '^VERSION=' Makefile.pre.in | cut -d'=' -f2 | tr -d ' ')
        if [ -z "$PYTHON_VERSION" ]; then
            # Fallback: extract version from configure.ac or Include/patchlevel.h
            PYTHON_VERSION=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:3])))" 2>/dev/null || echo "unknown")
        fi
        
        PYTHON_PREFIX="/opt/python/$PYTHON_VERSION"
        PYTHON_EXE="$PYTHON_PREFIX/bin/python3"

        # Configure with proper prefix and debug symbols
        ./configure \
            --prefix="$PYTHON_PREFIX" \
            --enable-loadable-sqlite-extensions \
            --with-openssl=$(brew --prefix openssl@3) \
            --with-pydebug

        # Build and install Python
        echo "Building Python $PYTHON_VERSION with debug symbols..."
        sudo make -j10
        sudo make install

        # Create symbolic links for convenience
        echo "Creating symbolic links..."
        sudo ln -sf "$PYTHON_PREFIX/bin/python3" "$PYTHON_PREFIX/bin/python"
        
        # Find the actual python binary name (e.g., python3.14)
        PYTHON_BINARY=$(find "$PYTHON_PREFIX/bin" -name "python3.*" -type f | head -n 1)
        if [ -n "$PYTHON_BINARY" ]; then
            PYTHON_BASENAME=$(basename "$PYTHON_BINARY")
            sudo ln -sf "$PYTHON_PREFIX/bin/$PYTHON_BASENAME" "$PYTHON_PREFIX/bin/python3"
            sudo ln -sf "$PYTHON_PREFIX/bin/pip${PYTHON_BASENAME#python}" "$PYTHON_PREFIX/bin/pip3"
            sudo ln -sf "$PYTHON_PREFIX/bin/pip${PYTHON_BASENAME#python}" "$PYTHON_PREFIX/bin/pip"
            sudo ln -sf "$PYTHON_PREFIX/bin/pydoc${PYTHON_BASENAME#python}" "$PYTHON_PREFIX/bin/pydoc"
            sudo ln -sf "$PYTHON_PREFIX/bin/idle${PYTHON_BASENAME#python}" "$PYTHON_PREFIX/bin/idle"
            sudo ln -sf "$PYTHON_PREFIX/bin/${PYTHON_BASENAME}-config" "$PYTHON_PREFIX/bin/python-config"
        fi

        # Upgrade pip and install essential tools
        echo "Upgrading pip and installing essential tools..."
        sudo "$PYTHON_EXE" -m pip install --upgrade pip setuptools wheel
        sudo "$PYTHON_EXE" -m pip install uv

    else
        echo "Only GNU+Linux and OSX are supported"
        exit 1
    fi

    # For Linux, use the local build
    if [ `uname` = "Linux" ];then
        make -j4
        PYTHON_EXE=python
    fi

    popd

    # create a new virtualenv with our debug python build using uv
    if [ `uname` = "Darwin" ];then
        # Use uv to create the virtual environment with the system-installed debug Python
        uv venv --python="$PYTHON_EXE" --seed .venv
        # add the python gdb debug script next to python binary in the venv
        cp submodules/cpython/Tools/gdb/libpython.py .venv/bin/python-gdb.py
    else
        # For Linux, create with local build
        LOCAL_PYTHON="$PWD/submodules/cpython/$PYTHON_EXE"
        uv venv --python="$LOCAL_PYTHON" --seed .venv
        # add the python gdb debug script next to python binary in the venv
        cp submodules/cpython/Tools/gdb/libpython.py .venv/bin/python-gdb.py
    fi

    # activate our venv
    source .venv/bin/activate

    # uv install the things needed to build the docs; ipython is for people
    # to use during the exercises
    uv pip install ipython sphinx sphinx-rtd-theme

    # build the sphinx project
    pushd tutorial
    make html
    popd

    ROOT=$PWD

    # make sure we can actually build stuff with this CPython
    pushd exercises/fib
    PYTHON_ASSERTION="
from fib import fib
assert fib(10) == 55, 'fib returned and unexpected value'
"
    if python setup.py build_ext --inplace && \
            python -c "$PYTHON_ASSERTION";then
        rm -r build/
        printf "\nvirtual environment created successfully: $(find $ROOT -maxdepth 1 -name .venv)\n"
        printf '\n\nEnvironment is setup correctly!\n'
    fi
    popd
)

if [ $? -eq 0 ];then
    # only activate the venv if the install steps worked, otherwise we mask the
    # error
    source .venv/bin/activate
else
    BOLD=$(tput bold)
    RED=$(tput setaf 1)
    NORMAL=$(tput sgr0)
    if [ $? -ne 0 ];then
        # don't fail to print at all because of tput
        BOLD=''
        RED=''
        NORMAL=''
    fi
    printf "\n\nEnvironment is $BOLD$RED**not**$NORMAL setup correctly!\n"
fi
```
