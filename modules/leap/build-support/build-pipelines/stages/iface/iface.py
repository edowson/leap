import os
import re
import sys
import string
import SCons.Script
import SCons.Util
import model
from model import  *
import bsv_tool


def getIfaceIncludeDirs(moduleList):
    global inc_dir
    global hw_dir
    return [inc_dir, hw_dir]

def getIfaceLibDirs(moduleList):
    global hw_bsc_dir
    return [hw_bsc_dir]


class Iface():

    def __init__(self, moduleList):

        # This function has the side effect of generating a header
        # file, which is needed by various dependency calculations. 
        bsv_tool.getBluespecVersion()

        ## Invoke a separate instance of SCons to compute both dependence
        ## (Bluespec needs a separate pass) and generate interface
        ## dictionaries.
        ##
        ## We do this for dictionaries because the set of files emitted
        ## is unpredictable from the inputs.  We can't predict the names
        ## of all source source files that may be generated in the iface
        ## tree for dictionaries and RRR.  SCons requires that dependence be
        ## computed on its first pass.
        ##
        if not moduleList.isDependsBuild and not moduleList.env.GetOption('clean'):
            # Convert command line ARGUMENTS dictionary to a string.
            # The build will be done in the local tree, so get rid of
            # the SCONSCRIPT argument.
            cmd_args = moduleList.arguments.copy()
            if ('SCONSCRIPT' in cmd_args):
                del cmd_args['SCONSCRIPT']
            args = ' '.join(['%s="%s"' % (k, v) for (k, v) in cmd_args.items()])
            print 'Building depends-init ' + args + '...'
            model.execute('scons depends-init ' + args)

        BSC = moduleList.env['DEFS']['BSC']
        TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
        ROOT_DIR_SW_INC = ":".join(moduleList.env['DEFS']['ROOT_DIR_SW_INC'].split(" ") + moduleList.env['DEFS']['SW_INC_DIRS'].split(" "))
        BSC_FLAGS_VERILOG = moduleList.env['DEFS']['BSC_FLAGS_VERILOG']

        moduleList.env['ENV']['SHELL'] = '/bin/sh'

        # First pass of LIM build may supply us with extra context for backend compilation. 
        if(re.search('\w', moduleList.getAWBParam('iface_tool', 'EXTRA_INC_DIRS'))):
            EXTRA_INC_DIRS = moduleList.getAWBParam('iface_tool', 'EXTRA_INC_DIRS')
            ROOT_DIR_SW_INC += ":" + EXTRA_INC_DIRS

        if not os.path.isdir('iface/build/include'):
            os.makedirs('iface/build/include')
            os.makedirs('iface/build/hw/' + TMP_BSC_DIR)
            # Backwards compatibility.
            os.symlink('awb', 'iface/build/include/asim')

        global inc_dir
        inc_dir = moduleList.env.Dir('iface/build/include')
        dict_inc_dir = inc_dir.Dir('awb/dict')
        rrr_inc_dir = inc_dir.Dir('awb/rrr')

        global hw_dir
        hw_dir = moduleList.env.Dir('iface/build/hw')
        global hw_bsc_dir
        hw_bsc_dir = hw_dir.Dir(TMP_BSC_DIR)

        self.dir_dict = moduleList.env.Dir('iface/src/dict')
        def addPathDic(path):
            return self.dir_dict.File(path)

        self.dir_rrr = moduleList.env.Dir('iface/src/rrr')
        def addPathRRR(path):
            return self.dir_rrr.File(path)

        if moduleList.env.GetOption('clean'):
            os.system('rm -rf iface/build')

        tgt = []
        d_tgt = []
        r_tgt = []

        # Convert ROOT_DIR_SW_INC to root-relative directories
        inc_dir_objs = map(moduleList.env.Dir, clean_split(ROOT_DIR_SW_INC, ':'))
        inc_dirs = ':'.join([d.path for d in inc_dir_objs])

        # Compile dictionary
        #  NOTE: this must run even if there are no dictionary files.  It always
        #  builds an init.h, even if it is empty.  That way any model can safely
        #  include init.h in a standard place.

        # First define an emitter that describes all the files generated by dictionaries
        self.all_gen_bsv = []
        def dict_emitter(target, source, env):        
            # Output file names are a function of the contents of dictionary files,
            # not the names of dictionary files.
            src_names = ''
            for s in source:
                src_names += ' ' + str(s)

            # Ask leap-dict for the output names based on the input file
            if (getBuildPipelineDebug(moduleList) != 0):
                print 'leap-dict --querymodules --src-inc ' + inc_dirs + ' ' + src_names +'\n'

            for d in os.popen('leap-dict --querymodules --src-inc ' + inc_dirs + ' ' + src_names).readlines():
                #
                # Querymodules describes both targets and dependence info.  Targets
                # are the first element of each line followed by a colon and a
                # space separated list of other dictionaries on which the target
                # depends, e.g.:
                #     STREAMS: STREAMS_A STREAMS_B
                #
                # Start by breaking the line into a one or two element array.  The
                # first element is a dictionary name.  The second element, if it
                # exists, is a list of other dictionaries on which the first element
                # depends.
                #
                tgt = d.rstrip().split(':')
                if (len(tgt) > 1):
                    tgt[1] = [x for x in tgt[1].split(' ') if x != '']

                # Add to the target list for the build
                target.append(dict_inc_dir.File(tgt[0] + '.bsh'))
                target.append(dict_inc_dir.File(tgt[0] + '.h'))

                # Build a list of BSV files for building later
                bsv = [hw_dir.File(tgt[0] + '_DICT.bsv')]
                target.append(bsv[0])
                if (len(tgt) > 1):
                    bsv.append([hw_dir.File(x + '_DICT.bsv') for x in tgt[1]])
                self.all_gen_bsv.append(bsv)
                
            return target, source

        # Define the dictionary builder
        # not really sure why srcs stopped working?
        # leap-configure creates this dynamic_params.dic. Gotta handle is specially. Boo.
        localDictionaries = moduleList.getAllDependencies('GIVEN_DICTS') 
        extra_dicts = []
        if (re.search('\w', moduleList.getAWBParam('iface_tool', 'EXTRA_DICTS'))):
            EXTRA_DICTS = moduleList.getAWBParam('iface_tool', 'EXTRA_DICTS')
            extra_dicts = EXTRA_DICTS.split(':') 

        # Generate a list of dictionaries as SCons File() objects
        dicts = map(addPathDic, set(localDictionaries + ['dynamic_params.dic'] + extra_dicts))

        # $SOURCES doesn't work for some reason when specifying multiple targets
        # using the Builder() method.  Convert dicts to a sorted list of strings.
        s_dicts = sorted([d.path for d in dicts])

        dictCommand = 'leap-dict --src-inc ' + \
                      inc_dirs + \
                      ' --tgt-inc ' + dict_inc_dir.path + \
                      ' --tgt-hw ' + hw_dir.path + \
                      ' ' + ' '.join(s_dicts)
        if (getBuildPipelineDebug(moduleList) != 0):
            print dictCommand

        d_bld = moduleList.env.Builder(action = dictCommand,
                                       emitter = dict_emitter)
        moduleList.env.Append(BUILDERS = {'DIC' : d_bld})

        # Add dependence info computed by previous dictionary builds (it uses cpp).
        for dic in dicts:
            d = '.depends-dic-' + os.path.basename(str(dic))
            moduleList.env.NoCache(d)
            moduleList.env.ParseDepends(d, must_exist = False)

        ##
        ## Finally, request dictionary build.  The dictionary is built
        ## during the "dependence" pass since the set of generated files
        ## is not known in advance.
        ##
        if (moduleList.isDependsBuild):
            d_tgt = moduleList.env.DIC(dict_inc_dir.File('init.h'), dicts)
            tgt += d_tgt

            def emit_dic_names(target, source, env):
                f = open(target[0].path, 'w')
                for bsv in env.Flatten(self.all_gen_bsv):
                    f.write(str(bsv) + '\n')
                f.close()

            # Emit the list of generated dictionaries
            tgt += moduleList.env.Command('iface/build/include/awb/dict/all_dictionaries.log',
                                          d_tgt,
                                          emit_dic_names)
        else:
            # Reload the list of generated dictionaries
            f = open('iface/build/include/awb/dict/all_dictionaries.log', 'r')
            for d in f:
                self.all_gen_bsv += [moduleList.env.File(d.rstrip())]
            f.close()

        # Add dependence info computed by previous RRR builds (it uses cpp).
        extra_rrrs = []
        localRRRs = moduleList.getAllDependenciesWithPaths('GIVEN_RRRS')
        if (re.search('\w', moduleList.getAWBParam('iface_tool', 'EXTRA_RRRS'))):
            EXTRA_RRRS = moduleList.getAWBParam('iface_tool', 'EXTRA_RRRS')
            extra_rrrs = EXTRA_RRRS.split(':') 

        rrrs = map(addPathRRR, set(localRRRs + extra_rrrs))

        # leap-rrr-stubgen generates dictionary entries in the order
        # received. Force this order to be lexical
        rrrs.sort()
        for rrr in rrrs:
            d = '.depends-rrr-' + os.path.basename(str(rrr))
            moduleList.env.NoCache(d)
            moduleList.env.ParseDepends(d, must_exist = False)

        # Compile RRR stubs
        #  NOTE: like dictionaries, some files must be created even when no .rrr
        #  files exist.
        generate_vico = ''
        if (moduleList.getAWBParam('iface_tool', 'GENERATE_VICO')):
            generate_vico = '--vico'

        stubgen = 'leap-rrr-stubgen ' + generate_vico + \
                  ' --incdirs ' + inc_dirs + \
                  ' --odir ' + rrr_inc_dir.path + \
                  ' --mode stub --target hw --type server $SOURCES'

        if (moduleList.isDependsBuild):
            r_tgt = moduleList.env.Command(rrr_inc_dir.File('service_ids.h'), rrrs, stubgen)
            tgt += r_tgt

        # The depends-init build must create dictionaries and stubs
        moduleList.topDependsInit += tgt

        #
        # Compile generated BSV stubs
        #
        def emitter_bo(target, source, env):
            if (bsv_tool.getBluespecVersion() < 26572):
                target.append(str(target[0]).replace('.bo', '.bi'))
            return target, source

        def compile_bo(source, target, env, for_signature):
            bdir = os.path.dirname(str(target[0]))

            # Older compilers don't put -bdir on the search path
            maybe_bdir_tgt = ''
            if (bsv_tool.getBluespecVersion() < 15480):
                maybe_bdir_tgt = ':' + bdir

            cmd = BSC + ' ' + BSC_FLAGS_VERILOG + \
                  ' -p +:' + inc_dir.path + ':' + hw_dir.path + maybe_bdir_tgt + \
                  ' -bdir ' + bdir + ' -vdir ' + bdir + ' -simdir ' + bdir + ' ' + \
                  str(source[0])
            return cmd

        bsc = moduleList.env.Builder(generator = compile_bo, suffix = '.bo', src_suffix = '.bsv',
                                     emitter = emitter_bo)

        moduleList.env.Append(BUILDERS = {'BSC' : bsc})

        #
        # Describe BSV builds.  At the same time collect a Python dictionary of the
        # targets of the BSV builds.
        #
        bsv_targets = {}
        if (not moduleList.isDependsBuild):
            for bsv in self.all_gen_bsv:
                bo = bsv.File(TMP_BSC_DIR + '/' + os.path.splitext(bsv.name)[0] + '.bo')
                bsv_targets[bsv.path] = moduleList.env.BSC(bo, bsv)
                tgt += bsv_targets[bsv.path]

        #
        # Build everything
        # 
        moduleList.topModule.moduleDependency['IFACE'] = tgt
        moduleList.topModule.moduleDependency['IFACE_HEADERS'] = d_tgt + r_tgt

        moduleList.env.NoCache(tgt)
        moduleList.env.NoCache(d_tgt)
        moduleList.env.NoCache(r_tgt)   

        moduleList.env.Alias('iface', tgt)
