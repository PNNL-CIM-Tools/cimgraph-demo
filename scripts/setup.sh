# Setup script will run post creation of the environment.
curl -sSL https://install.python-poetry.org | python3 -

git clone https://github.com/GRIDAPPSD/topology-processor -b dsa
cd topology_processor
poetry install
poetry build

pip install dist/*.whl
cd ../cimgraph-demo



