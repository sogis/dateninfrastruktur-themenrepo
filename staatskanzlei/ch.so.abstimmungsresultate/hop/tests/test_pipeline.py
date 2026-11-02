#!/usr/bin/env python3
"""Integration tests against an installed Hop; no application code is executed in Python."""

import argparse
import copy
import csv
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[4]
APP = ROOT / "staatskanzlei/abstimmungsresultate/hop"
V = "http://www.ech.ch/xmlns/eCH-0252/1"
D = "http://www.ech.ch/xmlns/eCH-0155/5"
DAY = "2026-03-08"
CSV_NAME = f"abstimmungsresultate_{DAY}.csv"
COLS = (
    "abstimmungstag geschaeft_id hauptgeschaeft_id geschaeftsgruppe_id bund_id "
    "ebene einflussbereich_id titel kurztitel geschaeftstyp gemeinde_bfs_nr gemeinde_name "
    "stimmberechtigte stimmberechtigte_schweizer stimmberechtigte_auslandschweizer "
    "stimmberechtigte_maennlich stimmberechtigte_weiblich stimmrechtsausweise_urne "
    "stimmrechtsausweise_brieflich vollstaendig_ausgezaehlt freigegeben_am gesperrt_am "
    "stimmbeteiligung_prozent stimmzettel_eingegangen stimmzettel_ungueltig "
    "stimmzettel_leer stimmzettel_gueltig ja_stimmen nein_stimmen "
    "stichfrage_hauptvorlage_stimmen stichfrage_gegenvorschlag_stimmen stimmen_ohne_antwort"
).split()
TITLE = 'Änderung; «Überprüfung» "Zürich"\nzweite Zeile'


def tag(name, ns=V):
    return f"{{{ns}}}{name}"


def add(parent, name, value=None, ns=V):
    node = ET.SubElement(parent, tag(name, ns))
    if value is not None:
        node.text = str(value)
    return node


def delivery():
    """CH/CT/MU delivery with all three subtypes, cross tables and optional NULLs."""
    root = ET.Element(tag("delivery"))
    header = add(root, "deliveryHeader")
    add(header, "messageId", "synthetic-delivery", "http://www.ech.ch/xmlns/eCH-0058/5")
    add(header, "messageDate", "2026-03-08T15:00:00+01:00", "http://www.ech.ch/xmlns/eCH-0058/5")
    add(header, "testDeliveryFlag", "true", "http://www.ech.ch/xmlns/eCH-0058/5")
    base = add(root, "voteBaseDelivery")
    add(base, "cantonId", 11)
    add(base, "pollingDay", DAY)
    for i in range(1, 5):
        info = add(base, "voteInfo")
        vote = add(info, "vote")
        add(vote, "voteIdentification", f"000{i}")
        if i in (2, 3):
            add(vote, "mainVoteIdentification", "0001")
        if i != 4:
            other = add(vote, "otherIdentification")
            add(other, "idName", "idBund")
            add(other, "id", "0068" if i in (1, 2) else "0069")
        add(vote, "pollingDay", DAY)
        domain = add(vote, "domainOfInfluence")
        add(domain, "domainOfInfluenceType", "CT" if i == 4 else "CH", D)
        add(domain, "domainOfInfluenceIdentification", "CH11" if i != 4 else "11", D)
        title = add(vote, "voteTitleInformation")
        add(title, "language", "de")
        add(title, "voteTitle", TITLE)
        if i != 4:
            add(title, "voteTitleShort", "Kurz")
        english = add(vote, "voteTitleInformation")
        add(english, "language", "en")
        add(english, "voteTitle", "Not the German title")
        add(vote, "voteSubType", i if i != 4 else 1)
        for bfs in (["0002421", "0002581"] if i != 4 else ["0002581"]):
            ci = add(info, "countingCircleInfo")
            circle = add(ci, "countingCircle")
            add(circle, "countingCircleId", bfs)
            add(circle, "countingCircleName", "Gemeinde Ä")
            add(circle, "domainOfInfluenceType", "MU")
            result = add(ci, "resultData")
            voters = add(result, "countOfVotersInformation")
            add(voters, "countOfVotersTotal", 20)
            for voter, sex, count in [(1, None, 18), (2, None, 2), (None, 1, 11),
                                       (None, 2, 9), (1, 1, 10), (2, 1, 1), (1, 2, 8), (2, 2, 1)]:
                if i == 4 and voter is not None:
                    continue
                subtotal = add(voters, "subtotalInfo")
                if voter is not None:
                    add(subtotal, "voterType", voter)
                if sex is not None:
                    add(subtotal, "sex", sex)
                add(subtotal, "countOfVoters", count)
            if i != 4:
                cards = add(result, "votingCardInformationType")
                add(cards, "countOfVotingCardsReceivedInBallotbox", 0)
                add(cards, "countOfVotingCardsReceivedByMail", 12)
                add(result, "releasedTimeStamp", "2026-03-08T12:30:00+02:00")
                add(result, "lockoutTimeStamp", "2026-03-08T10:45:00Z")
                add(result, "voterTurnout", "60.25")
            add(result, "fullyCountedTrue", "0" if i == 4 else "1")
            for name, count in [("receivedVotes", 12), ("receivedInvalidVotes", 1),
                                ("receivedEmptyVotes", 1), ("receivedValidVotes", 10),
                                ("countOfYesVotes", 4 if i == 3 else 6),
                                ("countOfNoVotes", 5 if i == 3 else 4)]:
                add(result, name, count)
            if i == 3:
                add(result, "countOfVotesWithoutAnswer", 1)
    municipal_info = copy.deepcopy(info)
    municipal_vote = municipal_info.find(tag("vote"))
    municipal_vote.find(tag("voteIdentification")).text = "0005"
    municipal_domain = municipal_vote.find(tag("domainOfInfluence"))
    municipal_domain.find(tag("domainOfInfluenceType", D)).text = "MU"
    municipal_domain.find(tag("domainOfInfluenceIdentification", D)).text = "0002581"
    base.append(municipal_info)
    add(base, "numberOfEntries", 5)
    return root


def votes(root):
    return root.findall(f"{tag('voteBaseDelivery')}/{tag('voteInfo')}/{tag('vote')}")


def results(root):
    return root.findall(f"{tag('voteBaseDelivery')}/{tag('voteInfo')}/{tag('countingCircleInfo')}/{tag('resultData')}")


class HopPipelineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = Path(tempfile.mkdtemp(prefix="ech0252-hop-test-"))
        cls.config = cls.work / "config"
        cls.config.mkdir()
        metadata = cls.config / "metadata/pipeline-run-configuration"
        metadata.mkdir(parents=True)
        shutil.copy(ROOT / "shared/hop/metadata/pipeline-run-configuration/launcher-local.json", metadata)
        cls.env = dict(os.environ, HOP_CONFIG_FOLDER=str(cls.config),
                       HOP_AUDIT_FOLDER=str(cls.work / "audit"), HOP_JAVA_HOME=str(OPTIONS.java_home))
        cls.hop = OPTIONS.hop_home.resolve()
        print(f"Hop logs and generated fixtures: {cls.work}", flush=True)

    def run_hop(self, root, label, expect_success=True, raw=None):
        folder = self.work / label
        folder.mkdir()
        source = folder / "Eingabe ä ; export.xml"
        if raw is None:
            ET.register_namespace("", V)  # Default namespace: deliberately not VeWork's prefix.
            ET.register_namespace("politics", D)
            ET.ElementTree(root).write(source, encoding="utf-8", xml_declaration=True)
        else:
            source.write_bytes(raw)
        output = folder / "Ausgabe ä ; CSV"
        output.mkdir()
        target = output / CSV_NAME
        sentinel = b"Existing output must survive invalid input.\n"
        target.write_bytes(sentinel)
        log = folder / "hop.log"
        with log.open("w") as stream:
            proc = subprocess.run([str(self.hop / "hop-run.sh"), "-f", str(APP / "abstimmungsresultate.hpl"),
                                   "-r", "launcher-local", "-p", f"INPUT_XML={source},OUTPUT_DIR={output}"],
                                  env=self.env, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=90)
        content = log.read_text()
        if expect_success:
            self.assertEqual(proc.returncode, 0, content)
            self.assertNotIn("Pipeline detected one or more transforms with errors", content)
            self.assertNotEqual(target.read_bytes(), sentinel)
            self.assertFalse(target.read_bytes().startswith(b"\xef\xbb\xbf"))
            with target.open(encoding="utf-8", newline="") as stream:
                reader = csv.DictReader(stream, delimiter=";")
                self.assertEqual(reader.fieldnames, COLS)
                rows = list(reader)
            self.assertEqual(len(list(output.iterdir())), 1, "Exactly one output CSV")
            return rows, content, source, output
        self.assertNotEqual(proc.returncode, 0, content)
        self.assertEqual(target.read_bytes(), sentinel, f"{label}: existing output was overwritten")
        self.assertEqual(len(list(output.iterdir())), 1, f"{label}: unexpected output file")

    def test_native_transforms_only(self):
        pipeline = ET.parse(APP / "abstimmungsresultate.hpl").getroot()
        allowed = {"GetVariable", "getXMLData", "Validator", "FilterRows", "WriteToLog", "SelectValues",
                   "Constant", "Coalesce", "Calculator", "ValueMapper", "ConcatFields", "SwitchCase",
                   "Abort", "SortRows", "TextFileOutput", "Dummy"}
        self.assertLessEqual({t.findtext("type") for t in pipeline.findall("transform")}, allowed)
        self.assertEqual({p.findtext("name") for p in pipeline.findall("info/parameters/parameter")},
                         {"INPUT_XML", "OUTPUT_DIR"})

    def test_csv_mapping_optional_values_and_offset_conversion(self):
        rows, log, _, output = self.run_hop(delivery(), "valid")
        self.assertEqual(len(rows), 7)
        self.assertEqual(log.count("WARNUNG: Bundes-ID mehrfach verwendet."), 1)
        self.assertIn("0068", log)
        self.assertEqual([r["geschaeft_id"] for r in rows], ["0001", "0001", "0002", "0002", "0003", "0003", "0004"])
        self.assertTrue(all(r["titel"] == TITLE for r in rows))
        for row in rows:
            if row["geschaeftstyp"] == "stichfrage":
                self.assertEqual([row[n] for n in ("ja_stimmen", "nein_stimmen")], ["", ""])
                self.assertEqual([row[n] for n in ("stichfrage_hauptvorlage_stimmen", "stichfrage_gegenvorschlag_stimmen")], ["4", "5"])
            else:
                self.assertEqual([row[n] for n in ("ja_stimmen", "nein_stimmen")], ["6", "4"])
                self.assertEqual([row[n] for n in ("stichfrage_hauptvorlage_stimmen", "stichfrage_gegenvorschlag_stimmen")], ["", ""])
                self.assertEqual(row["stimmen_ohne_antwort"], "")
        row = rows[0]
        self.assertEqual(row["gemeinde_bfs_nr"], "0002421")
        self.assertEqual(row["bund_id"], "0068")
        self.assertEqual(row["geschaeftsgruppe_id"], "0001")
        self.assertEqual(row["stimmberechtigte_schweizer"], "18")
        self.assertEqual(row["stimmberechtigte_auslandschweizer"], "2")
        self.assertEqual(row["stimmberechtigte_maennlich"], "11")
        self.assertEqual(row["stimmberechtigte_weiblich"], "9")
        self.assertEqual(row["stimmrechtsausweise_urne"], "0")
        self.assertEqual(row["stimmbeteiligung_prozent"], "60.25")
        self.assertEqual(row["freigegeben_am"], "2026-03-08T11:30:00+01:00")
        self.assertEqual(row["gesperrt_am"], "2026-03-08T11:45:00+01:00")
        self.assertEqual(row["vollstaendig_ausgezaehlt"], "true")
        cantonal = rows[-1]
        self.assertEqual(cantonal["vollstaendig_ausgezaehlt"], "false")
        self.assertEqual(cantonal["ebene"], "kanton")
        self.assertEqual({r["ebene"] for r in rows}, {"bund", "kanton"})
        self.assertNotIn("0005", {r["geschaeft_id"] for r in rows})
        for col in ["kurztitel", "bund_id", "stimmberechtigte_schweizer", "stimmberechtigte_auslandschweizer",
                    "stimmrechtsausweise_urne", "stimmrechtsausweise_brieflich", "freigegeben_am",
                    "gesperrt_am", "stimmbeteiligung_prozent"]:
            self.assertEqual(cantonal[col], "", col)
        self.assertIn('""Zürich""', (output / CSV_NAME).read_text())

    def test_delivery_without_duplicate_bund_ids(self):
        root = delivery()
        votes(root)[1].find(tag("otherIdentification") + "/" + tag("id")).text = "0070"
        rows, log, _, _ = self.run_hop(root, "valid_no_warning")
        self.assertEqual(len(rows), 7)
        self.assertNotIn("WARNUNG: Bundes-ID mehrfach verwendet.", log)

    def test_rejects_invalid_deliveries_without_overwriting(self):
        cases = {}

        def case(label):
            root = delivery()
            cases[label] = root
            return root

        results(case("last_row_sum"))[-1].find(tag("receivedVotes")).text = "13"
        results(case("last_row_answers"))[-1].find(tag("countOfNoVotes")).text = "5"
        results(case("negative_count"))[-1].find(tag("countOfYesVotes")).text = "-6"
        results(case("fractional_count"))[-1].find(tag("countOfYesVotes")).text = "6.5"
        results(case("overflow"))[-1].find(tag("countOfVotersInformation") + "/" + tag("countOfVotersTotal")).text = "9223372036854775808"
        result = results(case("missing_count"))[-1]
        result.remove(result.find(tag("countOfYesVotes")))
        add(results(case("bad_turnout"))[-1], "voterTurnout", "100.01")
        add(results(case("bad_timestamp"))[-1], "releasedTimeStamp", "2026-02-30T11:30:00+01:00")
        root = case("bad_day")
        root.find(tag("voteBaseDelivery") + "/" + tag("pollingDay")).text = "2026-02-30"
        for vote in votes(root):
            vote.find(tag("pollingDay")).text = "2026-02-30"
        votes(case("duplicate_vote"))[-1].find(tag("voteIdentification")).text = "0001"
        votes(case("duplicate_vote_with_whitespace"))[-1].find(tag("voteIdentification")).text = " 0001 "
        vote = votes(case("multiple_id_elements"))[-1]
        add(vote, "voteIdentification", "another-id")
        add(results(case("multiple_count_elements"))[-1], "countOfYesVotes", "999")
        root = case("duplicate_circle")
        circles = root.findall(".//" + tag("countingCircleId"))
        circles[1].text = circles[0].text
        votes(case("invalid_parent"))[1].find(tag("mainVoteIdentification")).text = "not-present"
        votes(case("parent_is_counterproposal"))[2].find(tag("mainVoteIdentification")).text = "0002"
        votes(case("self_reference"))[1].find(tag("mainVoteIdentification")).text = "0002"
        votes(case("unknown_subtype"))[-1].find(tag("voteSubType")).text = "4"
        case("unknown_circle").findall(".//" + tag("countingCircle") + "/" + tag("domainOfInfluenceType"))[-1].text = "BZ"
        votes(case("unknown_domain"))[-1].find(tag("domainOfInfluence") + "/" + tag("domainOfInfluenceType", D)).text = "BZ"
        case("wrong_count").find(tag("voteBaseDelivery") + "/" + tag("numberOfEntries")).text = "6"
        votes(case("date_mismatch"))[-1].find(tag("pollingDay")).text = "2026-06-14"
        title = votes(case("missing_german"))[-1].find(tag("voteTitleInformation"))
        title.find(tag("language")).text = "fr"
        vote = votes(case("duplicate_german"))[-1]
        vote.append(copy.deepcopy(vote.find(tag("voteTitleInformation"))))
        voters = results(case("duplicate_subtotal"))[-1].find(tag("countOfVotersInformation"))
        voters.append(copy.deepcopy(voters.find(tag("subtotalInfo"))))
        case("wrong_delivery").find(tag("voteBaseDelivery")).tag = tag("electionBaseDelivery")
        root = case("wrong_version")
        for node in root.iter():
            node.tag = node.tag.replace(V, V[:-1] + "2")
        root = case("municipal_only")
        for vote in votes(root):
            vote.find(tag("domainOfInfluence") + "/" + tag("domainOfInfluenceType", D)).text = "MU"
        for label, root in cases.items():
            with self.subTest(label=label):
                print(f"  Rejecting {label}", flush=True)
                self.run_hop(root, label, expect_success=False)
        with self.subTest(label="malformed_xml_at_end"):
            raw = ET.tostring(delivery(), encoding="utf-8")[:-8]
            self.run_hop(None, "malformed_xml_at_end", expect_success=False, raw=raw)

    def test_original_delivery_acceptance(self):
        if not OPTIONS.input_xml:
            self.skipTest("Pass --input-xml for the original VeWork acceptance file")
        root = ET.parse(OPTIONS.input_xml).getroot()
        rows, log, _, _ = self.run_hop(root, "original")
        self.assertEqual(len(rows), 1040)
        self.assertEqual({r["ebene"] for r in rows}, {"bund", "kanton"})
        self.assertEqual(len({r["geschaeft_id"] for r in rows}), 10)
        tie = [r for r in rows if r["geschaeftstyp"] == "stichfrage"]
        self.assertEqual(len(tie), 104)
        for col, value in [("stichfrage_hauptvorlage_stimmen", 36128),
                           ("stichfrage_gegenvorschlag_stimmen", 57240), ("stimmen_ohne_antwort", 3158)]:
            self.assertEqual(sum(int(r[col]) for r in tie), value)
        lookup = {(r["geschaeft_id"], r["gemeinde_bfs_nr"]): r for r in rows}
        for vote, fields, expected in [("IPQ237", ("ja_stimmen", "nein_stimmen"), ("123", "163")),
                                      ("IPQ238", ("ja_stimmen", "nein_stimmen"), ("203", "75")),
                                      ("IPQ239", ("stichfrage_hauptvorlage_stimmen", "stichfrage_gegenvorschlag_stimmen"), ("116", "154"))]:
            self.assertEqual(tuple(lookup[vote, "2421"][f] for f in fields), expected)
        self.assertEqual(lookup["IPQ237", "2581"]["stimmberechtigte"], "11458")
        self.assertNotIn(("IPQ247", "2581"), lookup)
        self.assertEqual({r["geschaeft_id"] for r in rows if r["bund_id"] == "6840"}, {"IPQ241", "IPQ242"})
        self.assertEqual(log.count("WARNUNG: Bundes-ID mehrfach verwendet."), 1)
        for row in rows:
            n = lambda col: int(row[col] or 0)
            self.assertEqual(n("stimmzettel_eingegangen"), n("stimmzettel_ungueltig") + n("stimmzettel_leer") + n("stimmzettel_gueltig"))
            self.assertEqual(n("stimmzettel_gueltig"), sum(n(f) for f in ["ja_stimmen", "nein_stimmen", "stichfrage_hauptvorlage_stimmen", "stichfrage_gegenvorschlag_stimmen", "stimmen_ohne_antwort"]))
        results(root)[-1].find(tag("receivedVotes")).text = "6101"
        self.run_hop(root, "original_last_row_error", expect_success=False)

    def test_installed_launcher(self):
        if not OPTIONS.launcher:
            self.skipTest("Pass --launcher to test the installed launcher execution service")
        _, _, source, output = self.run_hop(delivery(), "launcher_input")
        plugin = self.hop / "plugins/misc/hop-application-launcher"
        jars = list(plugin.glob("*.jar"))
        self.assertTrue(jars, f"No installed launcher at {plugin}")
        classes = self.work / "test-classes"
        classes.mkdir()
        classpath = os.pathsep.join([str(self.hop / "lib/core/*"), str(self.hop / "lib/swt/osx/arm64/*"),
                                    str(plugin / "*"), str(plugin / "lib/*")])
        subprocess.run([str(OPTIONS.java_home / "bin/javac"), "-proc:none", "-cp", classpath, "-d", str(classes),
                        str(APP / "tests/LauncherSmoke.java")], check=True, timeout=90)
        log = self.work / "launcher.log"
        with log.open("w") as stream:
            proc = subprocess.run([str(OPTIONS.java_home / "bin/java"),
                                   f"-DHOP_CONFIG_FOLDER={self.config}",
                                   f"-DHOP_AUDIT_FOLDER={self.work / 'audit'}",
                                   f"-DHOP_PLUGIN_BASE_FOLDERS={self.hop / 'plugins'}",
                                   "-cp", str(classes) + os.pathsep + classpath, "LauncherSmoke",
                                   str(ROOT), str(source), str(output), str(self.work / "launcher-reports")],
                                  stdout=stream, stderr=subprocess.STDOUT, timeout=90, cwd=self.hop)
        self.assertEqual(proc.returncode, 0, log.read_text())
        self.assertIn("LAUNCHER SUCCESS", log.read_text())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hop-home", type=Path, required=True)
    parser.add_argument("--java-home", type=Path, required=True)
    parser.add_argument("--input-xml", type=Path)
    parser.add_argument("--launcher", action="store_true")
    OPTIONS, rest = parser.parse_known_args()
    unittest.main(argv=[__file__] + rest, verbosity=2)
