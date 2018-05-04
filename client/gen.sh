protoc --python_out=. ../proto/src/protos/common/*.proto -I ../proto/src/protos/common/
protoc --python_out=. ../proto/src/protos/games/*.proto -I ../proto/src/protos/games/ -I ../proto/src/protos/common/
protoc --python_out=. ../proto/src/protos/*.proto -I ../proto/src/protos/ -I ../proto/src/protos/games/ -I ../proto/src/protos/common/
