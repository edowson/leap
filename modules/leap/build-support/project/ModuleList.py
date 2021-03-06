# -*-Python-*-

import os
import sys
import errno
import traceback

from SCons.Defaults import DefaultEnvironment

import pygraph
try:
  from pygraph.classes.digraph import digraph
except ImportError:
  # don't need to do anything
  print "\n"
  # print "Warning you should upgrade to pygraph 1.8"
import pygraph.algorithms.sorting
import Module
import Utils
import AWBParams
import ProjectDependency
import CommandLine
import Source

# Some helper functions for navigating the build tree

def get_build_path(moduleList, module):
  return moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath

def get_temp_path(moduleList, module):
  env = moduleList.env
  MODULE_PATH = get_build_path(moduleList, module)
  TMP_BSC_DIR = env['DEFS']['TMP_BSC_DIR']
  return MODULE_PATH + '/' + TMP_BSC_DIR + '/'

# The following funtions are used in several places throughout the
# code base.  It is not clear that they should be located here.
# Perhaps some other library code may be needed?
def get_wrapper(module):
    return module.name + '_Wrapper.bsv'

def get_log(module):
    return module.name + '_Log.bsv'

def get_logfile(moduleList,module):
    TEMP_PATH = get_temp_path(moduleList,module)
    return TEMP_PATH + get_wrapper(module).replace('.bsv', '.log')


# The module list class.  This class exists as an interface between
# AWB and the build pipeline. 

class ModuleList:
  
  def dump(self):
    print "compileDirectory: " + self.compileDirectory + "\n"
    print "Modules: "
    self.topModule.dump()  
    for module in self.moduleList:
      module.dump()
    print "\n"
    print "apmName: " + self.apmName + "\n"


  def __init__(self, env, modulePickle, arguments, cmdLineTgts):
      # do a pattern match on the synth boundary paths, which we need to build
      # the module structure
    self.env = env

    CommandBaseline = env.Command

    # override certain scons build functions to de-sugar
    # build-pipeline's object types.

    def CommandOverride(tgts, srcs, cmds):
        # did we get a flat object?
        srcsSugared = srcs
        if(not isinstance(srcs, list)):
            srcsSugared = [srcs]

        modifiedSrcs = []
        #might want convert dependencies here.        
        for src in srcsSugared:           
            if(isinstance(src, Source.Source)):
                modifiedSrcs.append(str(src))
            else:
                modifiedSrcs.append(src)

        return CommandBaseline(tgts, modifiedSrcs, cmds)

    self.env.Command = CommandOverride    

    self.arguments = arguments
    self.cmdLineTgts = cmdLineTgts
    self.buildDirectory = env['DEFS']['BUILD_DIR']
    self.compileDirectory = env['DEFS']['TMP_FPGA_DIR']
    givenVerilogs = Utils.clean_split(env['DEFS']['GIVEN_VERILOGS'], sep = ' ') 
    givenVerilogPkgs = Utils.clean_split(env['DEFS']['GIVEN_VERILOG_PKGS'], sep = ' ')
    givenVerilogHs = Utils.clean_split(env['DEFS']['GIVEN_VERILOG_HS'], sep = ' ') 
    givenNGCs = Utils.clean_split(env['DEFS']['GIVEN_NGCS'], sep = ' ') 
    givenVHDs = Utils.clean_split(env['DEFS']['GIVEN_VHDS'], sep = ' ') 
    self.apmName = env['DEFS']['APM_NAME']
    self.apmFile = env['DEFS']['APM_FILE']
    self.moduleList = []
    self.modules = {} # Convenient dictionary
    self.awbParamsObj = AWBParams.AWBParams(self)
    self.isDependsBuild = (CommandLine.getCommandLineTargets(self) == [ 'depends-init' ])


    
    #We should be invoking this elsewhere?
    #self.wrapper_v = env.SConscript([env['DEFS']['ROOT_DIR_HW_MODEL'] + '/SConscript'])

    # this really doesn't belong here. 
    if env['DEFS']['GIVEN_CS'] != '':
      SW_EXE_OR_TARGET = env['DEFS']['ROOT_DIR_SW'] + '/obj/' + self.apmName + '_sw.exe'
      SW_EXE = [SW_EXE_OR_TARGET]
    else:
      SW_EXE_OR_TARGET = '$TARGET'
      SW_EXE = []
    self.swExeOrTarget = SW_EXE_OR_TARGET
    self.swExe = SW_EXE

    self.swIncDir = Utils.clean_split(env['DEFS']['SW_INC_DIRS'], sep = ' ')
    self.swLibs = Utils.clean_split(env['DEFS']['SW_LIBS'], sep = ' ')
    self.swLinkLibs = Utils.clean_split(env['DEFS']['SW_LINK_LIBS'], sep = ' ')
    self.m5BuildDir = env['DEFS']['M5_BUILD_DIR'] 

    if len(env['DEFS']['GIVEN_ELFS']) != 0:
      elf = ' -bd ' + str.join(' -bd ',Utils.clean_split(env['DEFS']['GIVEN_ELFS'], sep = ' '))
    else:
      elf = ''
    self.elf = elf

    #
    # Use a cached post par ncd to guide map and par?  This is off by default since
    # the smart guide option can make place & route fail when it otherwise would have
    # worked.  It doesn't always improve run time, either.  To turn on smart guide
    # either define the environment variable USE_SMARTGUIDE or set
    # USE_SMARTGUIDE on the scons command line to a non-zero value.
    #
    self.smartguide_cache_dir = env['DEFS']['WORKSPACE_ROOT'] + '/var/xilinx_ncd'
    self.smartguide_cache_file = self.apmName + '_par.ncd'
    try:
        os.mkdir(self.smartguide_cache_dir)
    except OSError, e:
        if e.errno == errno.EEXIST: pass
        
    if (self.env['ENV'].has_key('USE_SMARTGUIDE') and
        (FindFile(self.apmName + '_par.ncd', [self.smartguide_cache_dir]) != None)):
      self.smartguide = ' -smartguide ' +  self.smartguide_cache_dir + '/' + self.smartguide_cache_file
    else:
      self.smartguide = ''

    # deal with other modules
    emit_override_params = not self.isDependsBuild
    Module.initAWBParamParser(arguments, emit_override_params)

    for module in sorted(modulePickle):
      # Loading module parameters delayed to here in order to support
      # command-line overrides.  Build a dictionary indexed by module name.
      self.awbParamsObj.parseModuleAWBParams(module)

      if self.env.GetOption('clean'):
        module.cleanAWBParams()

      # check to see if this is the top module (has no parent)
      if(module.parent == ''): 
        module.putAttribute('TOP_MODULE', True)
        self.topModule = module
      else:
        self.moduleList.append(module)

      self.modules[module.name] = module

      #This should be done in xst process 
      module.moduleDependency['VERILOG'] = givenVerilogs
      module.moduleDependency['VERILOG_PKG'] = givenVerilogPkgs
      module.moduleDependency['VERILOG_H'] = givenVerilogHs
      module.moduleDependency['BA'] = []
      module.moduleDependency['VERILOG_STUB'] = []
      module.moduleDependency['VERILOG_LIB'] = []
      module.moduleDependency['NGC'] = givenNGCs
      module.moduleDependency['VHD'] = givenVHDs

    for module in self.synthBoundaries():
      # each module has a generated bsv
      module.moduleDependency['VERILOG'] = ['hw/' + module.buildPath + '/.bsc/' + module.wrapperName() + '.v'] + givenVerilogs
      module.moduleDependency['VERILOG_PKG'] = givenVerilogPkgs
      module.moduleDependency['VERILOG_H'] = givenVerilogHs
      module.moduleDependency['VERILOG_LIB'] = []
      module.moduleDependency['BA'] = []
      module.moduleDependency['BSV_LOG'] = []
      module.moduleDependency['STR'] = []

    self.topModule.moduleDependency['VERILOG'] = ['hw/' + self.topModule.buildPath + '/.bsc/mk_' + self.topModule.name + '_Wrapper.v'] + givenVerilogs
    self.topModule.moduleDependency['VERILOG_PKG'] = givenVerilogPkgs
    self.topModule.moduleDependency['VERILOG_H'] = givenVerilogHs
    self.topModule.moduleDependency['VERILOG_STUB'] = []
    self.topModule.moduleDependency['VERILOG_LIB'] = []
    self.topModule.moduleDependency['NGC'] = givenNGCs
    self.topModule.moduleDependency['VHD'] = givenVHDs
    self.topModule.moduleDependency['UCF'] =  Utils.clean_split(self.env['DEFS']['GIVEN_UCFS'], sep = ' ')
    self.topModule.moduleDependency['XCF'] =  Utils.clean_split(self.env['DEFS']['GIVEN_XCFS'], sep = ' ')
    self.topModule.moduleDependency['SDC'] = Utils.clean_split(env['DEFS']['GIVEN_SDCS'], sep = ' ')
    self.topModule.moduleDependency['BA'] = []
    self.topModule.moduleDependency['BSV_LOG'] = []   # Synth boundary build log file
    self.topModule.moduleDependency['STR'] = []       # Global string table

    if (self.getAWBParam('model', 'LEAP_BUILD_CACHE_DIR') != ""):
      self.env.CacheDir(self.getAWBParam('model', 'LEAP_BUILD_CACHE_DIR'))

    try:
      self.localPlatformUID = self.getAWBParam('physical_platform_defs', 'FPGA_PLATFORM_ID')
      self.localPlatformName = self.getAWBParam('physical_platform_defs', 'FPGA_PLATFORM_NAME')
      if(self.localPlatformName != self.localPlatformName.lower()):
          print "Error: Platform name must be lower case (due to Bluespec). Fix your environment file." 
          exit(1)
      self.localPlatformValid = True
    except:
      self.localPlatformUID = 0
      self.localPlatformName = 'default'
      self.localPlatformValid = False

    self.topDependency = []
    self.topDependsInit = []

    self.graphize()
    self.graphizeSynth()

    # set up build target for various views of the AWB Parameters.
    def parameter_tcl_closure(moduleList, paramTclFile):
         def parameter_tcl(target, source, env):
             self.awbParamsObj.emitParametersTCL(paramTclFile)
         return parameter_tcl

    paramTclFile = self.compileDirectory + '/params.xdc'

    self.topModule.moduleDependency['PARAM_TCL'] = [paramTclFile]

    self.env.Command( 
        [paramTclFile],
        [],
        parameter_tcl_closure(self, paramTclFile)
        )                             


  def getAWBModule(self, moduleName):
      return self.modules[moduleName]
    
  def getAWBParam(self, moduleName, param):
      return self.awbParamsObj.getAWBParam(moduleName, param)

  def getAWBParamSafe(self, moduleName, param):
      return self.awbParamsObj.getAWBParamSafe(moduleName, param)

  def getAllDependencies(self, key):
      # we must check to see if the dependencies actually exist.
      # generally we have to make sure to remove duplicates
      allDeps = [] 
      if (self.topModule.moduleDependency.has_key(key)):
          for dep in self.topModule.moduleDependency[key]:
              if (allDeps.count(dep) == 0):
                  allDeps.extend(dep if isinstance(dep, list) else [dep])
      for module in self.moduleList:
          if (module.moduleDependency.has_key(key)):
              for dep in module.moduleDependency[key]: 
                  if (allDeps.count(dep) == 0):
                      allDeps.extend(dep if isinstance(dep, list) else [dep])

      if (len(allDeps) == 0 and CommandLine.getBuildPipelineDebug(self) > 1):
          sys.stderr.write("Warning: no dependencies were found")

      # Return a list of unique entries, in the process converting SCons
      # dependence entries to strings.
      return list(set(ProjectDependency.convertDependencies(allDeps)))

  def getDependencies(self, module, key):
    allDeps = module.getDependencies(key)
    if(len(allDeps) == 0 and CommandLine.getBuildPipelineDebug(self) > 1):
      sys.stderr.write("Warning: no dependencies were found")
   
    return allDeps



  def getModuleDependenciesWithPaths(self, module, key):
    allDeps = [] 
    if(module.moduleDependency.has_key(key)):
      for dep in module.moduleDependency[key]: 
        if(allDeps.count(dep) == 0):
          allDeps.append(module.buildPath + '/' + dep)
    return allDeps

  def getAllDependenciesWithPaths(self, key):
    # we must check to see if the dependencies actually exist.
    # generally we have to make sure to remove duplicates
    allDeps = [] 
    if(self.topModule.moduleDependency.has_key(key)):
      for dep in self.topModule.moduleDependency[key]:
        if(allDeps.count(dep) == 0):
          allDeps.append(self.topModule.buildPath + '/' + dep)

    for module in self.moduleList:
      allDeps += self.getModuleDependenciesWithPaths(module,key)

    if(len(allDeps) == 0 and CommandLine.getBuildPipelineDebug(self) > 1):
      sys.stderr.write("Warning: no dependencies were found")

    return allDeps

  # walk down the source tree from the given module to its leaves, 
  # which are either true leaves or underlying synth boundaries. 
  def getSynthBoundaryDependencies(self, module, key):
    # we must check to see if the dependencies actually exist.
    allDesc = self.getSynthBoundaryDescendents(module)

    # grab my deps
    # use hash to reduce memory usage
    allDeps = []
    for desc in allDesc:
      if(desc.moduleDependency.has_key(key)):
        for dep in desc.moduleDependency[key]:
          if(allDeps.count(dep) == 0):
            allDeps.extend([dep] if isinstance(dep, str) else dep)

    if(len(allDeps) == 0 and CommandLine.getBuildPipelineDebug(self) > 1):
      sys.stderr.write("Warning: no dependencies were found")
    
    return allDeps
  
  # returns the synthesis children of a given module.
  def getSynthBoundaryChildren(self, module):
    return self.graphSynth.neighbors(module)    

  # get everyone below this synth boundary
  # this is a recursive call
  def getSynthBoundaryDescendents(self, module):
    return self.getSynthBoundaryDescendentsHelper(True, module)
           
  ### FIX ME
  def getSynthBoundaryDescendentsHelper(self, ignoreSynth, module): 
    allDeps = []

    if(module.isSynthBoundary and not ignoreSynth):
      return allDeps

    # else return me
    allDeps = [module]

    neighbors = self.graph.neighbors(module)
    for neighbor in neighbors:
      allDeps += self.getSynthBoundaryDescendentsHelper(False,neighbor) 

    return allDeps

  # We carry around two representations of the source tree.  One is the 
  # original representation of the module tree, which will be helpful in 
  # gathering the sources of various modules.  The second is a tree of synthesis
  # boundaries, helpful, obviously, in actually constructing things.  
  
  def graphize(self):
    try:
      self.graph = pygraph.digraph()
    except (NameError, AttributeError):
      self.graph = digraph()   

    modules = [self.topModule] + self.moduleList
    # first, we must add all the nodes. Only then can we add all the edges
    self.graph.add_nodes(modules)

    # here we have a strictly directed graph, so we need only insert directed edges
    for module in modules:
      def checkParent(child):
        if module.name == child.parent:
          return True
        else:
          return False

      children = filter(checkParent, modules)
      for child in children:
        # due to compatibility issues, we need these try catch to pick the 
        # right function prototype.
        try:
          self.graph.add_edge(module,child) 
        except TypeError:
          self.graph.add_edge((module,child)) 
  # and this concludes the graph build


  # returns a dependency based topological sort of the source tree 
  def topologicalOrder(self):
       return pygraph.algorithms.sorting.topological_sorting(self.graph)

  def graphizeSynth(self):
    try:
      self.graphSynth = pygraph.digraph()
    except (NameError, AttributeError):
      self.graphSynth = digraph()
    modulesUnfiltered = [self.topModule] + self.moduleList
    # first, we must add all the nodes. Only then can we add all the edges
    # filter by synthesis boundaries
    modules = filter(checkSynth, modulesUnfiltered)
    self.graphSynth.add_nodes(modules)

    # here we have a strictly directed graph, so we need only insert directed edges
    for module in modules:
      def checkParent(child):
        if module.name == child.synthParent:
          return True
        else:
          return False

      children = filter(checkParent, modules)
      for child in children:
        #print "Adding p: " + module.name + " c: " + child.name
        try:
          self.graphSynth.add_edge(module,child) 
        except TypeError:
          self.graphSynth.add_edge((module,child)) 
  # and this concludes the graph build


  ## Returns a dependency based topological sort of the source tree 
  def topologicalOrderSynth(self):
    return pygraph.algorithms.sorting.topological_sorting(self.graphSynth)

  ## Return all modules that are synthesis boundaries.  This list does
  ## NOT include the top module.
  def synthBoundaries(self):
    return filter(checkSynth, self.moduleList)

  ## Adds a new module to the module list.  This get used dynamically in the build tree.
  def insertModule(self, newModule):
      if(isinstance(newModule, list)):
          def assignMod(mod):
             self.modules[mod.name] = mod
             return None
          self.moduleList += newModule
          map(assignMod, newModule)
      else:
          self.moduleList.append(newModule)
          self.modules[newModule.name] = newModule

##
## Helper functions
##


def checkSynth(module):
  return module.isSynthBoundary
