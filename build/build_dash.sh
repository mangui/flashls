#!/bin/bash
if [ -z "$FLEXPATH" ]; then
  echo "Usage FLEXPATH=/path/to/flex/sdk sh ./build.sh"
  exit
fi

OPT_DASH_DEBUG="-use-network=false \
    -optimize=true \
    -define=CONFIG::LOGGING,true \
    -define=CONFIG::DASH,true -define=CONFIG::HLS,false \
    -define=CONFIG::FLASH_11_1,true"

OPT_DASH_RELEASE="-use-network=false \
    -optimize=true \
    -define=CONFIG::LOGGING,false \
    -define=CONFIG::DASH,true -define=CONFIG::HLS,false \
    -define=CONFIG::FLASH_11_1,true"

OPT_DASH_DEBUG_10_1="-use-network=false \
    -optimize=true \
    -define=CONFIG::LOGGING,true \
    -define=CONFIG::DASH,true -define=CONFIG::HLS,false \
    -define=CONFIG::FLASH_11_1,false"

OPT_DASH_RELEASE_10_1="-use-network=false \
    -optimize=true \
    -define=CONFIG::LOGGING,false \
    -define=CONFIG::DASH,true -define=CONFIG::HLS,false \
    -define=CONFIG::FLASH_11_1,false"

# echo "Compiling bin/release/flashlsChromeless.swf"
# $FLEXPATH/bin/mxmlc ../src/org/mangui/player/chromeless/ChromelessPlayer.as \
#     -source-path ../src \
#     -o ../bin/release/flashlsChromeless.swf \
#     $OPT_DASH_RELEASE \
#     -library-path+=../lib/blooddy_crypto.swc \
#     -target-player="11.1" \
#     -default-size 480 270 \
#     -default-background-color=0x000000
# ./add-opt-in.py ../bin/release/flashlsChromeless.swf

echo "Compiling bin/debug/flashlsChromeless.swf"
$FLEXPATH/bin/mxmlc ../src/org/mangui/player/chromeless/ChromelessPlayer.as \
    -source-path ../src \
    -o ../bin/debug/flashlsChromeless.swf \
    $OPT_DASH_DEBUG \
    -library-path+=../lib/blooddy_crypto.swc \
    -target-player="11.1" \
    -default-size 480 270 \
    -default-background-color=0x000000
./add-opt-in.py ../bin/debug/flashlsChromeless.swf
