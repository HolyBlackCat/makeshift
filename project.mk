# $(call Library,box2d-2.4.1.tar.gz)
# $(call LibrarySetting,cmake_flags,-DBOX2D_BUILD_UNIT_TESTS:BOOL=OFF -DBOX2D_BUILD_TESTBED:BOOL=OFF)
# $(call LibrarySetting,deps,libogg-1.3.5)

# $(call Library,libogg-1.3.5.tar.gz)
# $(call LibrarySetting,build_system,configure_make)

# $(call Library,libvorbis-1.3.7.tar.gz)
# $(call LibrarySetting,deps,ogg-1.3.5)
# $(call LibrarySetting,build_system,configure_make)


# $(call Library,freetype-2.11.1.tar.gz)
# $(call Library,SDL2_net-2.0.1.tar.gz)

# $(call Library,zlib-1.2.11.tar.gz)

$(call Library,fmt-8.0.1.zip)
$(call LibrarySetting,cmake_flags,-DBUILD_SHARED_LIBS=ON)


$(call Project,exe,a)
$(call ProjectSetting,source_dirs,src/a)
$(call ProjectSetting,deps,b)

$(call Project,shared,b)
$(call ProjectSetting,source_dirs,src/b)
$(call ProjectSetting,libs,fmt-8.0.1)
$(call ProjectSetting,pch,*->src/b/pch.h)

CXXFLAGS := -DAAA='"global"'

$(call Mode,release)
$(call ModeSetting,CXXFLAGS,$(CXXFLAGS) -DBBB='"release"')
$(call Mode,debug)
$(call ModeSetting,CXXFLAGS,$(CXXFLAGS) -g -DBBB='"debug"')
