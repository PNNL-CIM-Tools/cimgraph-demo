# Setup script will run post creation of the environment.
curl -sSL https://install.python-poetry.org | python3 -
# Install GridAPPS-D Topology Processor
git clone https://github.com/GRIDAPPSD/topology-processor -b techfest_2023
cd topology-processor
poetry install
poetry build
cd ..
pip install -e topology-processor
# Install CIMHub
git clone https://github.com/GRIDAPPSD/CIMHub.git -b final9500
python3 -m pip install -e CIMHub

# Install CIMantic Graphs
git clone https://github.com/PNNL-CIM-Tools/CIM-Graph.git -b techfest_2023
cd CIM-Graph
poety install
poetry build
pip install dist/*.whl
cd ..
# Install DSS-Python
# pip install dss-python

# Install OpenDSSCMD 1.2.17
cd dss/opendsscmd_1.2.17
sudo cp opendsscmd /usr/local/bin
sudo cp lib* /usr/local/lib
sudo chmod +x /usr/local/bin/opendsscmd
sudo chmod +x /usr/local/lib/libklusolve.so
sudo chmod +x /usr/local/lib/liblinenoise.so
sudo apt-get update
sudo apt-get -y install libzmq5-dev
sudo apt-get -y install libczmq-dev
# cd ../../..
# mkdir Documents
# mkdir OpenDSSCmd

# Start blazegraph running on port 8889
docker run -d -p 8889:8080 gridappsd/blazegraph