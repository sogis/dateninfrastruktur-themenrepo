import ch.so.agi.hop.launcher.CatalogLoader;
import ch.so.agi.hop.launcher.ExecutionService;
import java.nio.file.Path;
import java.util.Map;
import org.apache.hop.core.HopEnvironment;

/** Test harness for the installed launcher JAR. This is never part of the Hop pipeline. */
public class LauncherSmoke {
  public static void main(String[] args) throws Exception {
    HopEnvironment.init();
    Path root = Path.of(args[0]);
    var app = new CatalogLoader().load(root).stream()
        .filter(a -> a.id().equals("staatskanzlei.abstimmungsresultate")).findFirst().orElseThrow();
    var outcome = new ExecutionService().run(root, "working-tree-test", app,
        Map.of("INPUT_XML", args[1], "OUTPUT_DIR", args[2]), Path.of(args[3]));
    if (!outcome.status().equals("SUCCESS")) {
      throw new AssertionError("Launcher failed: " + outcome.log());
    }
    System.out.println("LAUNCHER SUCCESS: " + app.title() + " — " + outcome.report());
  }
}
