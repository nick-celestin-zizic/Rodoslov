using Build    :: #import "ncz/Build";
using Basic    :: #import "Basic";
using Compiler :: #import "Compiler";
String  :: #import "String";
Process :: #import "Process";

android := !true;
#run,stallable {
    set_build_options_dc(.{do_output=false});
    set_working_directory(#filepath);
    
    w := add_workspace("Family Tree");
    {
        using options := get_build_options(w);
        defer set_build_options(options, w);
        
        user_data_string        = "main.jai";
        output_executable_name  = "Rodoslov";
        output_path             = #filepath;
        enable_bytecode_inliner = false;
        backend                 = .X64;
        
        set_optimization(*options, .VERY_DEBUG);
        
        if   os_target == .WINDOWS
        then additional_linker_arguments = .["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"];
    }
    
    add_plugin(w, "Check");
    if android {
        add_plugin(w, "Android/Toolchain", "-e");
        add_plugin(w, "Autorun(run_android)");
    } else {
        add_plugin(w, "Icon", "-icon", String.join(#filepath, "icon.ico"));
        add_plugin(w, "Autorun(run_debugger)");
        add_plugin(w, "ncz/Procedure_Finder");
        add_plugin(w, "ncz/tracy");
    }
    compile();
}

#poke_name Build run_android;
run_android :: (executable_path_without_extension: string, args: []string) {
    Process.run_command("android_helper.exe", "start");
}