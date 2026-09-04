cmake_minimum_required(VERSION 3.16)
project(sftp-dual-pane LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt5 5.11 REQUIRED COMPONENTS Core Gui Quick Qml Network)
find_package(OpenSSL REQUIRED)

# vendored libssh2（静态编译，避免依赖系统包）
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
add_subdirectory(thirdparty/libssh2 EXCLUDE_FROM_ALL)

add_executable(sftp-dual-pane
    src/main.cpp
    src/sftpclient.cpp
    src/dirmodel.cpp
    src/browsethread.cpp
    src/shellsession.cpp
    src/transferthread.cpp
    src/settingsstore.cpp
    resources.qrc
)

target_include_directories(sftp-dual-pane PRIVATE
    src
    thirdparty/libssh2/include
)

target_link_libraries(sftp-dual-pane PRIVATE
    Qt5::Core
    Qt5::Gui
    Qt5::Quick
    Qt5::Qml
    Qt5::Network
    libssh2
    OpenSSL::Crypto
)
