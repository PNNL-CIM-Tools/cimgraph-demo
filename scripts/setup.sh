# Setup script will run post creation of the environment.
curl -sSL https://install.python-poetry.org | python3 -
# Install GridAPPS-D Topology Processor
git clone https://github.com/GRIDAPPSD/topology-processor -b dsa
cd topology_processor
poetry install
poetry build
cd ..
pip install -e topology-processor
# Install CIMHub
git clone https://github.com/GRIDAPPSD/CIMHub.git -b final9500
python3 -m pip install -e CIMHub

# Install CIMantic Graphs
git clone https://github.com/PNNL-CIM-Tools/CIM-Graph.git -b techfest_2023
cd cimgraph-demo
poety install
poetry build
pip install dist/*.whl
# Install DSS-Python
pip install dss-python

