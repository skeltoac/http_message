# BEGIN CONFIG

# Where are the erl and app files?
SOURCEDIR   := src

# Where are the hrl files?
INCLUDEDIR  := include /lib/ejabberd/include /lib/ejabberd/include/mod_pubsub /lib/ejabberd/include/web

# Where shall the apps and beams be compiled?
TARGETDIR   := ebin

# Where shall the apps and beams be installed?
INSTALLDIR  := /lib/ejabberd/ebin

# Where are any extra code paths? (e.g. behaviour beams)
PREPENDPATH :=
APPENDPATH  := /lib/ejabberd/ebin

# END CONFIG

INCLUDEFLAGS := $(patsubst %,-I %, $(INCLUDEDIR))
SPECIALFLAGS := $(patsubst %,-pa %, $(PREPENDPATH)) $(patsubst %,-pz %, $(APPENDPATH))

MODULES  := $(patsubst $(SOURCEDIR)/%.erl,%,$(wildcard $(SOURCEDIR)/*.erl))
APPS     := $(patsubst $(SOURCEDIR)/%.app,%,$(wildcard $(SOURCEDIR)/*.app))

INCLUDES := $(wildcard $(INCLUDEDIR)/*.hrl)
TARGETS  := $(patsubst %,$(TARGETDIR)/%.beam,$(MODULES))
APPFILES := $(patsubst %,$(TARGETDIR)/%.app,$(APPS))

all : $(TARGETDIR) $(APPFILES) $(TARGETS)

$(TARGETDIR) :
	@echo "Creating target directory $(TARGETDIR)"
	@mkdir -p $(TARGETDIR)

$(TARGETS) : $(TARGETDIR)/%.beam: $(SOURCEDIR)/%.erl $(INCLUDES)
	@echo "Compiling module $*"
	@erlc $(INCLUDEFLAGS) $(SPECIALFLAGS) -o $(TARGETDIR) $<

$(APPFILES) : $(TARGETDIR)/%.app: $(SOURCEDIR)/%.app
	@echo "Copying application $*"
	@cp $< $@

e : $(TARGETDIR) $(APPFILES)
	@erl -noinput -eval 'case make:all() of up_to_date -> halt(0); _ -> halt(1) end.'

install : all
ifdef INSTALLDIR
	@echo "Copying to $(INSTALLDIR)"
	@install -m 644 $(TARGETDIR)/* $(INSTALLDIR)
endif

clean :
	@if [ -d $(TARGETDIR) ]; then \
		echo "Deleting ebin and app files from $(TARGETDIR)..."; \
		rm -f $(TARGETS) $(APPFILES); \
		rmdir $(TARGETDIR); \
	 else \
		echo "Nothing to clean."; \
	 fi
	@rm -f erl_crash.dump
