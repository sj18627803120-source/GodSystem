import java.io.*;
import java.lang.reflect.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.integration.expose.LuaJavaClassExposer;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import zombie.Lua.LuaManager;
import zombie.Lua.KahluaNumberConverter;
import zombie.core.Core;

// Isolated capability checks only. Never sends HTTP, starts a process,
// copies a loader, edits launch settings, or loads a world.
public class AIBootstrapProbe {
    private static int checks = 0;
    private static void check(String name, boolean pass) {
        if (!pass) throw new AssertionError(name);
        checks++;
        System.out.println("PASS " + name);
    }
    public static void main(String[] args) throws Exception {
        J2SEPlatform platform = new J2SEPlatform();
        KahluaTable env = platform.newEnvironment();
        KahluaTable os = (KahluaTable)env.rawget("os");
        check("Kahlua os.execute absent", os.rawget("execute") == null);
        check("Kahlua io absent", env.rawget("io") == null);
        check("Kahlua package absent", env.rawget("package") == null);
        check("Kahlua luajava absent", env.rawget("luajava") == null);
        check("Runtime denied by real bridge", LuaJavaClassExposer.isDisallowed(Runtime.class));
        check("ClassLoader denied by real bridge", LuaJavaClassExposer.isDisallowed(ClassLoader.class));
        check("Desktop denied by real bridge", LuaJavaClassExposer.isDisallowed(java.awt.Desktop.class));
        check("arbitrary AI URL rejected", !LuaManager.isIndieStoneUrl("https://example.com/v1/chat/completions"));
        check("official URL allowed", LuaManager.isIndieStoneUrl("https://projectzomboid.com/"));
        check("installer URL rejected", !LuaManager.isIndieStoneUrl("file:///C:/probe/installer.exe"));
        check("EXE cache writer rejected", LuaManager.GlobalObject.getFileWriter("probe.exe", true, false) == null);
        check("JAR cache writer rejected", LuaManager.GlobalObject.getFileWriter("probe.jar", true, false) == null);
        check("parent traversal cache writer rejected", LuaManager.GlobalObject.getFileWriter("../probe.ini", true, false) == null);
        check("absolute mod writer rejected", LuaManager.GlobalObject.getModFileWriter("probe", "C:/probe/config.json", true, false) == null);
        check("parent traversal mod writer rejected", LuaManager.GlobalObject.getModFileWriter("probe", "../probe.json", true, false) == null);
        DataOutputStream output = LuaManager.GlobalObject.getFileOutput("probe.bin.jar");
        check("binary cache staging available", output != null);
        output.writeInt(0x12345678);
        LuaManager.GlobalObject.endFileOutput();
        File staged = new File(zombie.ZomboidFileSystem.instance.getCacheDir(), "Lua/probe.bin.jar");
        check("staged bytes confined to isolated cache", staged.length() == 4 && staged.getCanonicalPath().startsWith(new File(System.getProperty("user.home")).getCanonicalPath() + File.separator));
        boolean originalDebug = Core.debug;
        try {
            Core.debug = true;
            Method validate = LuaManager.class.getDeclaredMethod("validateReflectionAccess", Object.class);
            validate.setAccessible(true);
            try {
                validate.invoke(null, Runtime.class);
                throw new AssertionError("debug reflection allowed Class");
            } catch (InvocationTargetException expected) {
                check("debug reflection still denies Class", expected.getCause() instanceof IllegalStateException);
            }
        } finally { Core.debug = originalDebug; }
        KahluaConverterManager converter = new KahluaConverterManager();
        KahluaNumberConverter.install(converter);
        LuaManager.Exposer exposer = new LuaManager.Exposer(converter, platform, env);
        exposer.exposeGlobalFunctions(new LuaManager.GlobalObject());
        KahluaThread thread = new KahluaThread(platform, env);
        thread.debugOwnerThread = Thread.currentThread();
        String lua = "assert(type(getFileWriter) == 'function'); "
            + "assert(getFileWriter('probe.exe', true, false) == nil); "
            + "assert(getModFileWriter('probe', 'C:/probe.json', true, false) == nil); "
            + "assert(os.execute == nil and package == nil and luajava == nil); "
            + "assert(execute == nil and loadJar == nil and loadLibrary == nil); return 'PASS actual global Kahlua calls'";
        LuaClosure closure = LuaCompiler.loadis(new StringReader(lua), "ai-bootstrap-probe", env);
        Object result = thread.call(closure, null, null, null);
        check("real global functions via Kahlua", "PASS actual global Kahlua calls".equals(result));
        System.out.println("CHECKS=" + checks);
        System.out.println("LIMIT=isolated native methods and global registration; not full game or network validation");
    }
}
