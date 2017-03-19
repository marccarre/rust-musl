#!/bin/bash -e

# Description:
# ------------
# Configures and compiles Rust to use MUSL in order to be able to statically
# link binaries. Indeed, at the time of writing this script Rust statically
# links all Rust libraries, but does not link libc/glibc which makes it harder
# to run Rust binaries in minimalistic containers.
# See also: https://doc.rust-lang.org/book/advanced-linking.html

# Variables:
RUST_VERSION="1.16.0"
MUSL_VERSION="1.1.16"
MUSL_GPG_KEY="3020450F"
LLVM_VERSION="4.0.0"
LLVM_GPG_KEY="345AD05D"
RKT_VERSION="1.25.0"
RKT_GPG_KEY="18AD5014C99EF7E3BA5F6CE950BDD3E0FC8A365E"
ACBUILD_VERSION="0.4.0"
ACBUILD_GPG_KEY="84580913"
DOCKER_GPG_KEY="58118E89F3A912897C070ADBF76221572C52609D"
IMAGE_NAME="rust-musl"

# Install dependencies:
sudo apt-get update -qq
sudo apt-get remove -qq -y make gcc g++ cmake git curl
sudo apt-get install -qq -y make gcc g++ cmake git curl

echo "> Building musl..."
mkdir -p dist
PREFIX=$(pwd)/dist
[ -f musl-"$MUSL_VERSION".tar.gz ] || curl -fsSO http://www.musl-libc.org/releases/musl-"$MUSL_VERSION".tar.gz
[ -f musl-"$MUSL_VERSION".tar.gz.asc ] || curl -fsSO http://www.musl-libc.org/releases/musl-"$MUSL_VERSION".tar.gz.asc
gpg --list-keys "$MUSL_GPG_KEY" || gpg --recv-key --keyserver hkp://p80.pool.sks-keyservers.net:80 "$MUSL_GPG_KEY"
gpg --verify musl-"$MUSL_VERSION".tar.gz.asc
[ -d musl-"$MUSL_VERSION" ] || tar xf musl-"$MUSL_VERSION".tar.gz
cd musl-"$MUSL_VERSION" || exit 1
./configure --disable-shared --prefix="$PREFIX"
make
make install
cd .. || exit 1
du -h dist/lib/libc.a

echo "> Building libunwind.a..."
[ -f llvm-"$LLVM_VERSION".src.tar.xz ] || curl -fsSO http://releases.llvm.org/"$LLVM_VERSION"/llvm-"$LLVM_VERSION".src.tar.xz
[ -f llvm-"$LLVM_VERSION".src.tar.xz.sig ] || curl -fsSO http://releases.llvm.org/"$LLVM_VERSION"/llvm-"$LLVM_VERSION".src.tar.xz.sig
gpg --list-keys "$LLVM_GPG_KEY" || gpg --recv-key --keyserver hkp://p80.pool.sks-keyservers.net:80 "$LLVM_GPG_KEY"
gpg --verify llvm-"$LLVM_VERSION".src.tar.xz.sig
[ -d llvm-"$LLVM_VERSION".src ] || tar xf llvm-"$LLVM_VERSION".src.tar.xz
cd llvm-"$LLVM_VERSION".src/projects/ || exit 1
[ -f libunwind-"$LLVM_VERSION".src.tar.xz ] || curl -fsSO http://releases.llvm.org/"$LLVM_VERSION"/libunwind-"$LLVM_VERSION".src.tar.xz
[ -f libunwind-"$LLVM_VERSION".src.tar.xz.sig ] || curl -fsSO http://releases.llvm.org/"$LLVM_VERSION"/libunwind-"$LLVM_VERSION".src.tar.xz.sig
gpg --verify libunwind-"$LLVM_VERSION".src.tar.xz.sig
[ -d libunwind ] || [ -d libunwind-"$LLVM_VERSION".src ] || tar xf libunwind-"$LLVM_VERSION".src.tar.xz
rm -f libunwind-"$LLVM_VERSION".src.tar.xz
rm -f libunwind-"$LLVM_VERSION".src.tar.xz.sig
[ -d libunwind ] || mv libunwind-"$LLVM_VERSION".src libunwind
mkdir -p libunwind/build
cd libunwind/build || exit 1
cmake -DLLVM_PATH=../../.. -DLIBUNWIND_ENABLE_SHARED=0 ..
make
cp lib/libunwind.a "$PREFIX"/lib/
cd ../../../../ || exit 1
du -h dist/lib/libunwind.a

echo "> Building musl-enabled rust..."
[ -d rust-"$RUST_VERSION" ] || git clone https://github.com/rust-lang/rust.git rust-"$RUST_VERSION"
cd rust-"$RUST_VERSION" || exit 1
[ "$(git branch | grep '\*' | cut -d ' ' -f2)" == "$RUST_VERSION" ] || git checkout tags/"$RUST_VERSION" -b "$RUST_VERSION"
./configure --target=x86_64-unknown-linux-musl --musl-root="$PREFIX" --prefix="$PREFIX"
make
make install
cd .. || exit 1
du -h rust-"$RUST_VERSION"/bin/rustc

echo "> Installing rkt..."
[ -f rkt_"$RKT_VERSION"-1_amd64.deb ]     || wget --quiet https://github.com/coreos/rkt/releases/download/v"$RKT_VERSION"/rkt_"$RKT_VERSION"-1_amd64.deb
[ -f rkt_"$RKT_VERSION"-1_amd64.deb.asc ] || wget --quiet https://github.com/coreos/rkt/releases/download/v"$RKT_VERSION"/rkt_"$RKT_VERSION"-1_amd64.deb.asc
gpg --recv-key --keyserver hkp://p80.pool.sks-keyservers.net:80 "$RKT_GPG_KEY"
gpg --verify rkt_"$RKT_VERSION"-1_amd64.deb.asc
sudo dpkg -i rkt_"$RKT_VERSION"-1_amd64.deb

echo "> Installing acbuild..."
[ -f acbuild-v"$ACBUILD_VERSION".tar.gz ]     || wget --quiet https://github.com/containers/build/releases/download/v"$ACBUILD_VERSION"/acbuild-v"$ACBUILD_VERSION".tar.gz
[ -f acbuild-v"$ACBUILD_VERSION".tar.gz.asc ] || wget --quiet https://github.com/containers/build/releases/download/v"$ACBUILD_VERSION"/acbuild-v"$ACBUILD_VERSION".tar.gz.asc
gpg --recv-key --keyserver hkp://p80.pool.sks-keyservers.net:80 "$ACBUILD_GPG_KEY"
gpg --verify acbuild-v"$ACBUILD_VERSION".tar.gz.asc
[ -d acbuild-v"$ACBUILD_VERSION" ] || tar xzf acbuild-v"$ACBUILD_VERSION".tar.gz
sudo cp acbuild-v"$ACBUILD_VERSION"/* /usr/local/bin
sudo ./rust-musl.acb

echo "> Installing Docker..."
sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys "$DOCKER_GPG_KEY"
sudo apt-add-repository 'deb https://apt.dockerproject.org/repo ubuntu-xenial main'
sudo apt-get update
sudo apt-get install -qq -y docker-engine
sudo docker build --tag="$IMAGE_NAME" --tag="$IMAGE_NAME":"$RUST_VERSION" --tag=quay.io/"$IMAGE_NAME" --tag=quay.io/"$IMAGE_NAME":"$RUST_VERSION" --build-arg=version_tag="$RUST_VERSION" .
sudo docker login docker.io -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD"
sudo docker login quay.io   -u "$QUAY_USERNAME" -p "$QUAY_PASSWORD"
sudo docker push quay.io/"$QUAY_USERNAME"/"$IMAGE_NAME"

echo "> Done."
