import java.io.*;
import java.lang.reflect.*;
import sun.misc.Unsafe;
import zombie.Lua.KahluaNumberConverter;
import zombie.characters.IsoPlayer;
import zombie.characters.Moodles.Moodles;
import zombie.characters.BodyDamage.BodyDamage;
import zombie.scripting.objects.MoodleType;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.vm.*;
import se.krka.kahlua.converter.*;
import se.krka.kahlua.integration.expose.LuaJavaClassExposer;
import se.krka.kahlua.luaj.compiler.LuaCompiler;

// Isolated fixtures supply strength/moodles; the weight setters/getters and
// BodyDamage.UpdateStrength below are the unmodified installed game methods.
public class CarryNativeProbe {
    public static class Player extends IsoPlayer {
        public Moodles fixtureMoodles;
        public BodyDamage fixtureBody;
        public KahluaTable fixtureData;
        public float strengthFactor;
        public Player() { super(null); }
        public float getWeightMod() { return strengthFactor; }
        public Moodles getMoodles() { return fixtureMoodles; }
        public BodyDamage getBodyDamage() { return fixtureBody; }
        public KahluaTable getModData() { return fixtureData; }
        public String getUsername() { return "carry-probe"; }
    }
    public static class Status extends Moodles {
        public int hunger;
        public Status() { super(null); }
        public int getMoodleLevel(MoodleType type) { return type == MoodleType.HUNGRY ? hunger : 0; }
    }
    public static void main(String[] args) throws Exception {
        Field uf = Unsafe.class.getDeclaredField("theUnsafe"); uf.setAccessible(true);
        Unsafe unsafe = (Unsafe)uf.get(null);
        J2SEPlatform platform = new J2SEPlatform();
        KahluaTable env = platform.newEnvironment();
        Player player = (Player)unsafe.allocateInstance(Player.class);
        Status status = (Status)unsafe.allocateInstance(Status.class);
        BodyDamage body = (BodyDamage)unsafe.allocateInstance(BodyDamage.class);
        Field parent = BodyDamage.class.getDeclaredField("parentChar"); parent.setAccessible(true); parent.set(body, player);
        player.fixtureMoodles = status; player.fixtureBody = body;
        player.fixtureData = platform.newTable(); player.strengthFactor = 1.58f;
        player.setMaxWeightBase(8); player.setMaxWeightDelta(1.0f);
        KahluaConverterManager converter = new KahluaConverterManager();
        KahluaNumberConverter.install(converter);
        LuaJavaClassExposer exposer = new LuaJavaClassExposer(converter, platform, env, env) {
            public boolean shouldExpose(Class<?> clazz) { return clazz != null && (clazz == Player.class || clazz == Status.class || clazz == BodyDamage.class || clazz.isAssignableFrom(Player.class) || clazz.isAssignableFrom(Status.class)); }
        };
        exposer.exposeLikeJava(Player.class);
        exposer.exposeLikeJava(BodyDamage.class);
        exposer.exposeLikeJava(Status.class);
        env.rawset("player", player); env.rawset("body", body); env.rawset("moodles", status);
        KahluaThread thread = new KahluaThread(platform, env); thread.debugOwnerThread = Thread.currentThread();
        LuaClosure script = LuaCompiler.loadis(new InputStreamReader(new FileInputStream(args[0]), "ISO-8859-1"), args[0], env);
        System.out.println(thread.call(script, null, null, null));
    }
}
