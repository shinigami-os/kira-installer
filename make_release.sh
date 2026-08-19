VERISON=26.08-1
SAVE_TO="../../SynologyDrive/Code_things/Others/Kira-Linux-Milestones/"

mkdir -p "$SAVE_TO"/"$VERISON"

echo "Building console ISO..."
sudo make clean && sudo make console
echo "Saving console ISO..."
cp build/kira-console.iso "$SAVE_TO"/"$VERISON"/

echo "Building desktop Sleex ISO..."
sudo make clean && sudo make desktop DE=sleex
echo "Saving desktop Sleex ISO..."
cp build/kira-desktop-sleex.iso "$SAVE_TO"/"$VERISON"/

echo "Building desktop SwayFX ISO..."
sudo make clean && sudo make desktop DE=swayFX
echo "Saving desktop SwayFX ISO..."
cp build/kira-desktop-swayFX.iso "$SAVE_TO"/"$VERISON"/

echo ""
echo "Done !"