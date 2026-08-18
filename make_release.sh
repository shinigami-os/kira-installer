VERISON=26.08-1
SAVE_TO="../../SynologyDrive/Code_things/Others/Kira-Linux-Milestones/"


echo "Building console ISO..."
make clean && make console

echo "Building desktop Sleex ISO..."
make clean && make desktop DE=sleex

echo "Building desktop SwayFX ISO..."
make clean && make desktop DE=swayFX

echo "Saving ISOs..."
mkdir -p "$SAVE_TO"/"$VERISON"
cp build/kira-*.iso "$SAVE_TO"/"$VERISON"/