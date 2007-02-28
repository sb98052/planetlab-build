#
# PlanetLab RPM generation
#
# Mark Huang <mlhuang@cs.princeton.edu>
# Copyright (C) 2003-2006 The Trustees of Princeton University
#
# $Id$
#

# Base rpmbuild in the current directory
export HOME := $(shell pwd)
export CVSROOT CVS_RSH

#
# Create spec file
#

SPECFILE := SPECS/$(notdir $(SPEC))

$(SPECFILE):
	mkdir -p SPECS
	echo "%define pldistro $(PLDISTRO)" > $@
ifeq ($(TAG),HEAD)
        # Define date for untagged builds
	echo "%define date $(shell date +%Y.%m.%d)" >> $@
else
        # Define cvstag for tagged builds
	echo "%define cvstag $(TAG)" >> $@
endif
	$(if $($(package)-SVNPATH),\
  svn cat $($(package)-SVNPATH)/$(SPEC) >> $@,\
  cvs -d $(CVSROOT) checkout -r $(TAG) -p $(SPEC) >> $@)


#
# Parse spec file into Makefile fragment
#

MK := tmp/$(package).mk

parseSpec: CFLAGS := -g -Wall

parseSpec: LDFLAGS := -lrpm -lrpmbuild

$(MK): $(SPECFILE) parseSpec .rpmmacros
	mkdir -p tmp
	./parseSpec $(RPMFLAGS) $(SPECFILE) > $@

# Defines SOURCES, SRPM, RPMS
include $(MK)

#
# Generate tarball(s)
#

# Get rid of any extensions
stripext = \
$(patsubst %.tar.bz2,%, \
$(patsubst %.tar.gz,%, \
$(patsubst %.tgz,%, \
$(patsubst %.zip,%, \
$(patsubst %.tar,%,$(1))))))

SOURCEDIRS := $(call stripext,$(SOURCES))

# Thierry - Jan 29 2007
# Allow different modules to have  different CVSROOT
# and/or to be extracted from their SVNPATH
#
# is there a single module ? to mimick cvs export -d behaviour
MULTI_MODULE := $(word 2,$(MODULE))
ifeq "$(MULTI_MODULE)" ""
# single module: do as before
SOURCES/$(package):
	mkdir -p SOURCES
	$(if $($(package)-SVNPATH),\
  cd SOURCES && svn export $($(package)-SVNPATH) $(package),\
  cd SOURCES && cvs -d $(CVSROOT) export -r $(TAG) -d $(package) $(MODULE))
else
# multiple modules : iterate 
SOURCES/$(package):
	mkdir -p SOURCES/$(package) && cd SOURCES/$(package) && (\
	$(foreach module,$(MODULE),\
	 $(if $($(module)-SVNPATH), \
  svn export $($(module)-SVNPATH) $(module), \
  cvs -d $(if $($(module)-CVSROOT),$($(module)-CVSROOT),$(CVSROOT)) export -r $(TAG)  $(module);\
         )))
endif

# Make a hard-linked copy of the exported directory for each Source
# defined in the spec file. However, our convention is that there
# should be only one Source file and one CVS module per RPM. It's okay
# if the CVS module consists of multiple directories, as long as the
# spec file knows what's going on.
$(SOURCEDIRS): SOURCES/$(package)
	cp -rl $< $@

.SECONDARY: SOURCES/$(package) $(SOURCEDIRS)

# Generate tarballs
SOURCES/%.tar.bz2: SOURCES/%
	tar cpjf $@ -C SOURCES $*

SOURCES/%.tar.gz: SOURCES/%
	tar cpzf $@ -C SOURCES $*

SOURCES/%.tgz: SOURCES/%
	tar cpzf $@ -C SOURCES $*

SOURCES/%.zip: SOURCES/%
	cd SOURCES && zip -r ../$@ $*

SOURCES/%.tar: SOURCES/%
	tar cpf $@ -C SOURCES $*

#
# Build
#

all: $(RPMS) $(SRPM)

# Build RPMS
$(RPMS): $(SPECFILE) $(SOURCES)
	mkdir -p BUILD RPMS
	$(RPMBUILD) $(RPMFLAGS) -bb $<

# Make the rest of the RPMS depend on the first one since building one
# builds them all.
ifneq ($(words $(RPMS)),1)
$(wordlist 2,$(words $(RPMS)),$(RPMS)): $(firstword $(RPMS))
endif

# Build SRPM
$(SRPM): $(SPECFILE) $(SOURCES)
	mkdir -p SRPMS
	rpmbuild $(RPMFLAGS) -bs $<

# Base rpmbuild in the current directory
.rpmmacros:
	echo "%_topdir $(HOME)" > $@
	echo "%_tmppath $(HOME)/tmp" >> $@

# Remove files generated by this package
clean:
	rm -rf \
	$(RPMS) $(SRPM) \
	$(patsubst SOURCES/%,BUILD/%,$(SOURCEDIRS)) \
	$(SOURCES) $(SOURCEDIRS) SOURCES/$(package) \
	$(MK) $(SPECFILE)

.PHONY: all clean

#################### convenience, for debugging only
# make +foo : prints the value of $(foo)
# make ++foo : idem but verbose, i.e. foo=$(foo)
++%: varname=$(subst +,,$@)
++%:
	@echo $(varname)=$($(varname))
+%: varname=$(subst +,,$@)
+%:
	@echo $($(varname))
