import os
import errno
import re
import SCons.Script  

from model import  *

#
# Generate path string to add source file into the Synplify project
#
def _generate_synplify_include(file):
    # Check for relative/absolute path
    directoryFix = ''
    if (not re.search('^\s*/',file)):  directoryFix = '../'

    type = 'unknown'
    prefix = ''
    if (re.search('\.ngc\s*$',file)):  
        type = 'ngc'
    if (re.search('\.v\s*$',file)):    
        type = 'verilog'
    if (re.search('\.sv\s*$',file)):    
        type = 'verilog'
        prefix = ' -vlog_std sysv '
    if (re.search('\.vhdl\s*$',file)):  
        type = 'vhdl'
    if (re.search('\.vhd\s*$',file)):  
        type = 'vhdl'
    if (re.search('\.sdc\s*$',file)):  
        type = 'constraint'

    # don't include unidentified files
    if(type == 'unknown'):
        return ''

    return 'add_file -' + type + prefix + ' \"'+ directoryFix + file + '\"\n'


def _filter_file_add(file, moduleList):
  # Check for relative/absolute path   
  output = ''
  for line in file.readlines():
      output += re.sub('add_file.*$','',line)
      if (getBuildPipelineDebug(moduleList) != 0):
          print 'converted ' + line + 'to ' + re.sub('add_file.*$','',line)

  return output;



# Converts Xilinx SRR file into resource representation which can be used
# by the LIM compiler to assign modules to execution platforms.
def getSRRResourcesClosureXilinx(module):

    attributes = {'LUT': "Total  LUTs:",'Reg': "Register bits not including I/Os:", 'BRAM': "Occupied Block RAM sites"}

    return getSRRResourcesClosureBase(module, attributes)


# Converts Altera SRR file into resource representation which can be used
# by the LIM compiler to assign modules to execution platforms.
def getSRRResourcesClosureAltera(module):

    attributes = {'LUT': "Total combinational functions ",'Reg': "Total registers ", 'M9Ks:': "Occupied Block RAM sites"}

    return getSRRResourcesClosureBase(module, attributes)


# General function for building an attribute collection from a synthesis report. 
# Used by the LIM compiler to assign modules to execution platforms.
# Also used to do automated placement for LI Modules. 
def getSRRResourcesClosureBase(module, attributes):

    def collect_srr_resources(target, source, env):

        srrFile = str(source[0])
        rscFile = str(target[0])

        srrHandle = open(srrFile, 'r')
        rscHandle = open(rscFile, 'w')
        resources =  {}

        for line in srrHandle:
            for attribute in attributes:
                if (re.match(attributes[attribute],line)):
                    match = re.search(r'\D+:\D+(\d+)', line)
                    if(match):
                        resources[attribute] = [match.group(1)]

        resourceString = ':'.join([resource + ':' + resources[resource][0] for resource in resources]) + '\n'

        rscHandle.write(module.name + ':')
        rscHandle.write(resourceString)
                                   
        rscHandle.close()
        srrHandle.close()
    return collect_srr_resources

def buildModuleEDF(moduleList, module, globalVerilogs, globalVHDs, resourceCollector):
    MODEL_CLOCK_FREQ = moduleList.getAWBParam('clocks_device', 'MODEL_CLOCK_FREQ')

    # need to eventually break this out into a seperate function
    # first step - modify prj options file to contain any generated wrappers
    prjFile = open('config/' + moduleList.apmName  + '.synplify.prj','r');  
    newPrjPath = 'config/' + module.wrapperName()  + '.modified.synplify.prj'
    newPrjFile = open(newPrjPath,'w');  

    newPrjFile.write('add_file -verilog \"../hw/'+module.buildPath + '/.bsc/' + module.wrapperName()+'.v\"\n');      

    # now dump all the 'VERILOG' 
    fileArray = globalVerilogs + globalVHDs + \
                moduleList.getDependencies(module, 'VERILOG_STUB') + \
                map(lambda x: moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + x, moduleList.getAllDependenciesWithPaths('GIVEN_SYNPLIFY_VERILOGS')) + \
                moduleList.getAllDependencies('NGC') + \
                moduleList.getAllDependencies('SDC')

    for file in fileArray:
        if(type(file) is str):
            newPrjFile.write(_generate_synplify_include(file))        
        else:
            if(getBuildPipelineDebug(moduleList) != 0):
                print type(file)
                print "is not a string"

    # Set up new implementation
    build_dir = moduleList.compileDirectory + '/' + module.wrapperName()
    try:
        os.mkdir(build_dir)
    except OSError, err:
        if err.errno != errno.EEXIST: raise 


    # establish an include path for synplify.  This is necessary for true text inclusion in verilog,
    # as raw text files don't always compile standalone. Ugly yes, but it is verilog....
    newPrjFile.write('set_option -include_path {')
    newPrjFile.write(";".join(["../" + moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleDir.buildPath for moduleDir in moduleList.synthBoundaries()] + [moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleDir.buildPath for moduleDir in moduleList.synthBoundaries()] + [moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + moduleDir.buildPath + '/.bsv/' for moduleDir in moduleList.synthBoundaries()]))
    newPrjFile.write('}\n')

    # once we get synth boundaries up, this will be needed only for top level
    newPrjFile.write('set_option -disable_io_insertion 1\n')
    newPrjFile.write('set_option -multi_file_compilation_unit 1\n')

    newPrjFile.write('set_option -frequency ' + str(MODEL_CLOCK_FREQ) + '\n')

    newPrjFile.write('impl -add ' + module.wrapperName()  + ' -type fpga\n')

    #dump synplify options file
    # MAYBE NOT A GOOD IDEA
    newPrjFile.write(_filter_file_add(prjFile, moduleList))

    #write the tail end of the options file to actually do the synthesis
    newPrjFile.write('set_option -top_module '+ module.wrapperName() +'\n')
    newPrjFile.write('project -result_file \"../' + build_dir + '/' + module.wrapperName() + '.edf\"\n')
     
    newPrjFile.write('impl -active \"'+ module.wrapperName() +'\"\n');

    # Enable advanced LUT combining
    newPrjFile.write('set_option -enable_prepacking 1\n')

    newPrjFile.write('project -run hdl_info_gen fileorder\n');
    newPrjFile.write('project -run constraint_check\n');
    newPrjFile.write('project -run synthesis\n');

    newPrjFile.close();
    prjFile.close();

    edfFile = build_dir + '/' +  module.wrapperName() + '.edf'
    resourceFile = build_dir + '/' + module.wrapperName() + '.resources'
    srrFile = build_dir + '/' + module.wrapperName()  + '.srr'

    if(not 'GEN_NGCS' in module.moduleDependency):
        module.moduleDependency['GEN_NGCS'] = [edfFile]
    else:
        module.moduleDependency['GEN_NGCS'] += [edfFile]
      
    sub_netlist = moduleList.env.Command(
      [edfFile, srrFile],
      moduleList.getAllDependencies('VERILOG') +
      moduleList.getAllDependencies('VERILOG_STUB') +
      moduleList.getAllDependencies('VERILOG_LIB') +
      [ newPrjPath ] +
      ['config/' + moduleList.apmName + '.synplify.prj'],
      [ SCons.Script.Delete(srrFile),
        'synplify_premier -batch -license_wait ' + newPrjPath + '> ' + build_dir + '.log',
        # Files in coreip just copied from elsewhere and waste space
        SCons.Script.Delete(build_dir + '/coreip'),
        '@echo synplify_premier ' + module.wrapperName() + ' build complete.' ])    

    module.moduleDependency['SYNTHESIS'] = [sub_netlist]
    module.moduleDependency['RESOURCES'] = [resourceFile]

    moduleList.env.Command(resourceFile,
                           srrFile,
                           resourceCollector(module))

    # we must gather resources files for the lim build. 
    if(moduleList.getAWBParam('bsv_tool', 'BUILD_LOGS_ONLY') or True):
        moduleList.topDependency += [resourceFile]      

    SCons.Script.Clean(sub_netlist, build_dir + '/' + module.wrapperName() + '.srr')
    SCons.Script.Clean(sub_netlist, 'config/' + module.wrapperName() + '.modified.synplify.prj')   

    return sub_netlist