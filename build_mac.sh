#!/usr/bin/env bash
set -e
# prerequisite: Qt >= 6.7 and Xcode command line tools

cd "$(dirname "$0")"

# Honor the Qt installation documented in README.md, or use qmake on PATH.
if [[ -n "${Qt6_DIR:-}" ]]; then
    QMAKE="$Qt6_DIR/bin/qmake"
else
    QMAKE="$(command -v qmake || true)"
fi
if [[ ! -x "$QMAKE" ]]; then
    echo "Error: qmake not found. Set Qt6_DIR to a Qt >= 6.7 installation." >&2
    exit 1
fi
if ! QT_VERSION="$("$QMAKE" -query QT_VERSION)"; then
    echo "Error: cannot run $QMAKE. Set Qt6_DIR to a compatible Qt >= 6.7 installation." >&2
    exit 1
fi
IFS=. read -r QT_MAJOR QT_MINOR QT_PATCH <<< "$QT_VERSION"
if [[ "$QT_MAJOR" != 6 || "$QT_MINOR" -lt 7 ]]; then
    echo "Error: Qt 6.7 or newer Qt 6 is required; found $QT_VERSION ($QMAKE)." >&2
    exit 1
fi
QT_BINS="$("$QMAKE" -query QT_INSTALL_BINS)"
MACDEPLOYQT="$QT_BINS/macdeployqt"
if [[ ! -x "$MACDEPLOYQT" ]]; then
    echo "Error: macdeployqt not found in $QT_BINS." >&2
    exit 1
fi
echo "Using Qt $QT_VERSION ($QMAKE)"
QT_ARCHDATA="$("$QMAKE" -query QT_INSTALL_ARCHDATA)"
for module in core gui widgets network quickwidgets svg texttospeech opengl openglwidgets; do
    if [[ ! -f "$QT_ARCHDATA/mkspecs/modules/qt_lib_$module.pri" ]]; then
        echo "Error: Qt $QT_VERSION is missing the $module module. Install it for this Qt installation." >&2
        exit 1
    fi
done

#sys_glut_clfags=`pkg-config --cflags glut gl`
#sys_glut_libs=`pkg-config --libs glut gl`
#sys_harfbuzz_clfags=`pkg-config --cflags harfbuzz`
#sys_harfbuzz_libs=`pkg-config --libs harfbuzz`

if [ -z ${MAKE_PARALLEL+x} ]; then export MAKE_PARALLEL=1; else echo "MAKE_PARALLEL defined"; fi
echo "MAKE_PARALLEL set to $MAKE_PARALLEL"

cd mupdf
#make USE_SYSTEM_HARFBUZZ=yes USE_SYSTEM_GLUT=yes SYS_GLUT_CFLAGS="${sys_glut_clfags}" SYS_GLUT_LIBS="${sys_glut_libs}" SYS_HARFBUZZ_CFLAGS="${sys_harfbuzz_clfags}" SYS_HARFBUZZ_LIBS="${sys_harfbuzz_libs}" -j 4
make HAVE_GLUT=no -j$MAKE_PARALLEL
cd ..

DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion | cut -d. -f1)}"

if [[ $1 == portable ]]; then
	"$QMAKE" pdf_viewer_build_config.pro -after "QMAKE_MACOSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET"
else
	"$QMAKE" "CONFIG+=non_portable" pdf_viewer_build_config.pro -after "QMAKE_MACOSX_DEPLOYMENT_TARGET=$DEPLOYMENT_TARGET"
fi

make -j$MAKE_PARALLEL

rm -rf build 2> /dev/null
mkdir build
mv sioyek.app build/
cp -r pdf_viewer/shaders build/sioyek.app/Contents/Resources/shaders

cp pdf_viewer/prefs.config build/sioyek.app/Contents/Resources/prefs.config
cp pdf_viewer/prefs_user.config build/sioyek.app/Contents/Resources/prefs_user.config
cp pdf_viewer/keys.config build/sioyek.app/Contents/Resources/keys.config
cp pdf_viewer/keys_user.config build/sioyek.app/Contents/Resources/keys_user.config
cp tutorial.pdf build/sioyek.app/Contents/Resources/tutorial.pdf

# Capture the current PATH
CURRENT_PATH=$(echo $PATH)

# Define the path to the Info.plist file inside the app bundle
INFO_PLIST="build/sioyek.app/Contents/Info.plist"

# Add LSEnvironment key with PATH to Info.plist
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$INFO_PLIST" || echo "LSEnvironment already exists"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:PATH string $CURRENT_PATH" "$INFO_PLIST" || /usr/libexec/PlistBuddy -c "Set :LSEnvironment:PATH $CURRENT_PATH" "$INFO_PLIST"

# Hack is required to avoid race condition in macos in CI
# See https://github.com/actions/runner-images/issues/7522
if [[ -n "$GITHUB_ACTIONS" ]]; then
  echo killing...; sudo pkill -9 XProtect >/dev/null || true;
  echo waiting...; while pgrep XProtect; do sleep 3; done;
fi

sleep 5

# mac deploys with qml currently don't work due to a qt bug
# macdeployqt build/sioyek.app -qmldir=./pdf_viewer/touchui -dmg
"$MACDEPLOYQT" build/sioyek.app -dmg
if [[ ! -f build/sioyek.dmg ]]; then
    echo "Error: macdeployqt did not create build/sioyek.dmg." >&2
    exit 1
fi

codesign --force --deep --sign - build/sioyek.app

zip -r sioyek-release-mac.zip build/sioyek.dmg
