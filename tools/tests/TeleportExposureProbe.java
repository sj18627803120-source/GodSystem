import java.io.*;
import java.lang.reflect.*;
import sun.misc.Unsafe;
import zombie.Lua.LuaManager;
import zombie.characters.NetworkPlayerAI;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.converter.*;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

// Read-only API visibility probe: no world, connection, or packet is created.
public class TeleportExposureProbe {
    public static void main(String[] args) throws Exception {
        J2SEPlatform p=new J2SEPlatform(); KahluaTable env=p.newEnvironment();
        LuaManager.Exposer e=new LuaManager.Exposer(new KahluaConverterManager(),p,env);
        LuaManager.env=env; LuaManager.exposer=e;
        zombie.core.random.RandStandard.INSTANCE.init();
        try { e.exposeAll(); } catch (Throwable initialization) {
            // The complete whitelist is filled before exposing static game
            // singletons, which need a world. Report this boundary explicitly.
            System.out.println("No-world initialization boundary: "+initialization.getClass().getName());
        }
        System.out.println("NetworkPlayerAI exposed="+e.shouldExpose(NetworkPlayerAI.class));
        System.out.println("GameServer exposed="+e.shouldExpose(zombie.network.GameServer.class));
        Field f=Unsafe.class.getDeclaredField("theUnsafe"); f.setAccessible(true);
        env.rawset("ai",((Unsafe)f.get(null)).allocateInstance(NetworkPlayerAI.class));
        KahluaThread thread=new KahluaThread(p,env);thread.debugOwnerThread=Thread.currentThread();
        LuaClosure script=LuaCompiler.loadis(new StringReader("local ok,value=pcall(function() return ai.resetSpeedLimiter end); return tostring(ok)..' / '..tostring(value)"),"exposure",env);
        System.out.println(thread.call(script,null,null,null));
    }
}
