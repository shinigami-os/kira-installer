VERISON=26.09-2

set -e

echo "Building console ISO..."
sudo make clean && sudo make console
echo "=========================== Saving console ISO... ==========================="
../kira-base/scripts/push-iso-release.sh $VERISON console

echo "Building desktop Sleex ISO..."
sudo make clean && sudo make desktop DE=sleex
echo "=========================== Saving desktop Sleex ISO... ==========================="
../kira-base/scripts/push-iso-release.sh $VERISON sleex

echo ""
echo "Done ! "
