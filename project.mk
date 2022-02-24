$(call Library,box2d-2.4.1.tar.gz)
$(call LibrarySetting,cmake_flags,-DBOX2D_BUILD_UNIT_TESTS:BOOL=OFF -DBOX2D_BUILD_TESTBED:BOOL=OFF)
# $(call LibrarySetting,deps,libogg-1.3.5)

$(call Library,libogg-1.3.5.tar.gz)
$(call LibrarySetting,build_system,configure_make)

$(call Library,libvorbis-1.3.7.tar.gz)
$(call LibrarySetting,deps,libogg-1.3.5)
# $(call LibrarySetting,build_system,configure_make)


$(call Library,freetype-2.11.1.tar.gz)
$(call Library,SDL2_net-2.0.1.tar.gz)

$(call Library,zlib-1.2.11.tar.gz)
