#!/usr/bin/python3

import sys
import argparse
import logging
from pathlib import Path
import json

import requests


class CveFetcher:
    baseurl = "https://services.nvd.nist.gov/rest/json/cves/2.0"

    def __init__(self):
        self.log = logging.getLogger(self.__class__.__name__)

    def get_parser(self) -> argparse.ArgumentParser:
        p = argparse.ArgumentParser(
            formatter_class=argparse.ArgumentDefaultsHelpFormatter
        )
        p.add_argument(
            "--config-dir",
            type=Path,
            default=str(Path("~/.local/share/cveinfo/").expanduser()),
        )
        p.add_argument(
            "--log-level", choices=["DEBUG", "INFO", "WARN", "ERROR"], default="INFO"
        )
        p.set_defaults(func=None)
        sub = p.add_subparsers()

        fetch = sub.add_parser("fetch")
        fetch.set_defaults(func=self.main_fetch)
        fetch.add_argument("--overwrite", action="store_true", default=False)
        fetch.add_argument("cveid", help="Example: CVE-2014-0160", nargs="+")

        cat = sub.add_parser("cat")
        cat.add_argument("cveid", help="Example: CVE-2014-0160", nargs="+")
        cat.set_defaults(func=self.main_cat)

        search = sub.add_parser("search")
        search.set_defaults(func=self.main_search)
        output = search.add_argument_group("output")
        output.add_argument(
            "--output-cve",
            default="cveid",
            choices=["cveid", "nvd-url", "nvd-json"],
            help="What to display",
        )

        results = search.add_argument_group("results")
        results.add_argument(
            "--show-missing-data",
            action="store_true",
            default=False,
            help=(
                "This will include CVEs for which we don't have relevant metrics"
                "as positive matches"
            ),
        )

        query = search.add_argument_group("query")
        query.add_argument("--min-score", type=float)
        query.add_argument(
            "--min-confidentiality-impact", choices=["LOW", "MEDIUM", "HIGH"]
        )
        query.add_argument("--min-integrity-impact", choices=["LOW", "MEDIUM", "HIGH"])
        query.add_argument(
            "--min-availability-impact", choices=["LOW", "MEDIUM", "HIGH"]
        )
        search.add_argument("cveid", help="Example: CVE-2014-0160", nargs="+")
        return p

    def get_path_for_cve(self, cve: str):
        return self.args.config_dir / "nvd" / f"{cve}.json"

    def fetch(self, cve: str):
        fpath = self.get_path_for_cve(cve)
        if not self.args.overwrite and fpath.exists():
            self.log.debug("%s already downloaded, skipping", cve)
            return
        resp = requests.get(self.baseurl, params={"cveId": cve})
        if not resp.ok:
            self.log.warn("Could not fetch %s", cve)
            return
        content = resp.json()  # check if json is valid
        with fpath.open(mode="w") as buf:
            json.dump(content["vulnerabilities"][0]["cve"], buf, indent=2)

    def main(self):
        p = self.get_parser()
        self.args = p.parse_args()
        logging.basicConfig(level=self.args.log_level)

        if self.args.func is None:
            print("No subcommand specified")
            p.print_usage()
            sys.exit(1)
        self.args.func()

    def main_fetch(self):
        self.args.config_dir.mkdir(exist_ok=True)
        for cve in self.args.cveid:
            self.fetch(cve)

    def vuln_match(self, vuln: dict) -> bool:
        impact_to_number = {
            "NONE": 0,
            "LOW": 10,
            "MEDIUM": 20,
            "HIGH": 30,
        }

        if not vuln["metrics"]:
            return self.args.show_missing_data
        metrics = vuln["metrics"]["cvssMetricV31"][0]["cvssData"]
        if self.args.min_score is not None:
            if metrics["baseScore"] < self.args.min_score:
                return False

        for impact in ["confidentiality", "integrity", "availability"]:
            option = getattr(self.args, f"min_{impact}_impact")
            if option is None:
                continue
            metric = f"{impact}Impact"
            if impact_to_number[metrics[metric]] < impact_to_number[option]:
                return False

        return True

    def output_cve(self, cve: str):
        match self.args.output_cve:
            case "cveid":
                print(cve)
            case "nvd-url":
                print(f"https://nvd.nist.gov/vuln/detail/{cve}")
            case "nvd-json":
                print(f"{self.baseurl}?cveId={cve}")

    def main_cat(self):
        for cve in self.args.cveid:
            path = self.get_path_for_cve(cve)
            print(path.open().read())

    def main_search(self):
        for cve in self.args.cveid:
            self.log.debug("Analyzing %s", cve)
            path = self.get_path_for_cve(cve)
            if not path.exists():
                self.log.error("You should fetch %s first", cve)
                sys.exit(1)
            vuln = json.load(path.open())
            if self.vuln_match(vuln):
                self.output_cve(cve)


if __name__ == "__main__":
    CveFetcher().main()
