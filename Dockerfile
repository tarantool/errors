FROM tarantool/tarantool:1.x-centos7

RUN yum -y install luarocks &&\
    tarantoolctl rocks install luacov --server=http://rocks.moonscript.org &&\
    luarocks install luacov-coveralls
