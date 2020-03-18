cmake_minimum_required(VERSION 2.8 FATAL_ERROR)

project(errors C)

set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})
set(CMAKE_SKIP_INSTALL_ALL_DEPENDENCY TRUE)

# Find Tarantool and Lua dependecies
set(TARANTOOL_FIND_REQUIRED ON)
find_package(Tarantool)
include_directories(${TARANTOOL_INCLUDE_DIRS})

file(GLOB_RECURSE LUA_FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/errors.lua"
  "${CMAKE_CURRENT_SOURCE_DIR}/errors/*.lua"
)

## API doc ####################################################################
###############################################################################

set(DOC_OUTPUT ${CMAKE_CURRENT_SOURCE_DIR}/doc/index.html)

if(DEFINED ENV{CMAKE_LDOC_FIND_REQUIRED})
  set(LDOC_FIND_REQUIRED "$ENV{CMAKE_LDOC_FIND_REQUIRED}")
endif()
find_package(Ldoc)

add_custom_command(
  OUTPUT DOC_OUTPUT
  COMMAND ${LDOC} --all .
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  DEPENDS ${LUA_FILES}
  COMMENT "Building API documentation"
  VERBATIM
)

if(LDOC_FOUND)
  add_custom_target(doc ALL
    DEPENDS DOC_OUTPUT)
else()
  add_custom_target(doc
    DEPENDS DOC_OUTPUT)
endif()

## Testing ####################################################################
###############################################################################

enable_testing()

add_test(
  NAME lint
  COMMAND luacheck errors-scm-1.rockspec
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

add_test(
  NAME test_unit
  COMMAND ${TARANTOOL} ${CMAKE_CURRENT_SOURCE_DIR}/taptest.lua
  WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

## Install ####################################################################
###############################################################################

install(
  DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}
  DESTINATION ${TARANTOOL_INSTALL_LUADIR}
)

install(
  FILES ${CMAKE_CURRENT_SOURCE_DIR}/errors.lua
  DESTINATION ${TARANTOOL_INSTALL_LUADIR}
)
