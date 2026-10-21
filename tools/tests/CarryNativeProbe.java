import java.io.*;
import java.lang.reflect.*;
import sun.misc.Unsafe;
import zombie.Lua.KahluaNumberConverter;
import zombie.characters.IsoPlayer;
import zombie.characters.traits.CharacterTraits;
import zombie.scripting.objects.CharacterTrait;
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
        public double probeTimeNanos() { return (double)System.nanoTime(); }
        public void setFixtureWeightFactor(float value) { strengthFactor = value; }
        public void setFixtureHunger(int value) { ((Status)fixtureMoodles).hunger = value; }
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
        player.setHealth(100.0f); body.setOverallBodyHealth(100.0f);
        player.fixtureData = platform.newTable(); player.strengthFactor = 1.58f;
        Field traitField = zombie.characters.IsoGameCharacter.class.getDeclaredField("characterTraits");
        traitField.setAccessible(true); traitField.set(player, new CharacterTraits());
        player.setMaxWeightBase(8); player.setMaxWeightDelta(1.0f);
        KahluaConverterManager converter = new KahluaConverterManager();
        KahluaNumberConverter.install(converter);
        LuaJavaClassExposer exposer = new LuaJavaClassExposer(converter, platform, env, env) {
            public boolean shouldExpose(Class<?> clazz) { return clazz != null && (clazz == Player.class || clazz == Status.class || clazz == BodyDamage.class || clazz == CharacterTraits.class || clazz == CharacterTrait.class || clazz.isAssignableFrom(Player.class) || clazz.isAssignableFrom(Status.class)); }
        };
        exposer.exposeLikeJava(Player.class);
        exposer.exposeLikeJava(BodyDamage.class);
        exposer.exposeLikeJava(Status.class);
        exposer.exposeLikeJava(CharacterTraits.class);
        exposer.exposeLikeJava(CharacterTrait.class);
        KahluaTable traitTokens = platform.newTable();
        for (String key : new String[]{"STRONG", "WEAK", "FEEBLE", "STOUT"}) {
            traitTokens.rawset(key, CharacterTrait.class.getField(key).get(null));
        }
        env.rawset("CharacterTrait", traitTokens);
        KahluaTable fixtures = platform.newTable();
        fixtures.rawset(1.0, player);
        for (int i = 2; i <= 100; i++) {
            Player extra = (Player)unsafe.allocateInstance(Player.class);
            Status extraStatus = (Status)unsafe.allocateInstance(Status.class);
            BodyDamage extraBody = (BodyDamage)unsafe.allocateInstance(BodyDamage.class);
            parent.set(extraBody, extra); traitField.set(extra, new CharacterTraits());
            extra.fixtureMoodles = extraStatus; extra.fixtureBody = extraBody;
            extra.fixtureData = platform.newTable(); extra.strengthFactor = 1.58f;
            extra.setHealth(100.0f); extraBody.setOverallBodyHealth(100.0f);
            extra.setMaxWeightBase(8); extra.setMaxWeightDelta(1.0f);
            fixtures.rawset((double)i, extra);
        }
        env.rawset("nativePlayers", fixtures);
        env.rawset("player", player); env.rawset("body", body); env.rawset("moodles", status);
        KahluaThread thread = new KahluaThread(platform, env); thread.debugOwnerThread = Thread.currentThread();
        LuaClosure script = LuaCompiler.loadis(new InputStreamReader(new FileInputStream(args[0]), "ISO-8859-1"), args[0], env);
        System.out.println(thread.call(script, null, null, null));
    }
}
