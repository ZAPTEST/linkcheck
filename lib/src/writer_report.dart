library linkcheck.writer_report;

import 'dart:io' show Stdout;
import 'dart:io' hide Link;
import 'dart:math' show min;

import 'package:console/console.dart';

import 'crawl.dart' show CrawlResult;
import 'link.dart';
import 'destination.dart';

void reportToFiles(String outputFolder, CrawlResult result) {
  // Checked URLs
  List<Destination> checkedUrls = result.destinations
      .where((destination) => !destination.wasDeniedByRobotsTxt && !destination.isUnsupportedScheme).toList(growable: false);

  var linksFile = File(outputFolder + '\\links.txt').openWrite();
  var lastOriginUri = "";
  for (var link in result.links) {
    var originUri = link.origin.uri.toString();
    var destinationUri = link.destination.uri.toString();
    if (lastOriginUri != originUri) {
      linksFile.write("- ${originUri}\r\n");
      lastOriginUri = originUri;
    }
    linksFile.write("= ${destinationUri}\r\n");
    if (link.destination.redirects != null) {
      for (var redirect in link.destination.redirects) {
        linksFile.write("> ${redirect.url}\r\n");
      }
    }
  }
  linksFile.close();

  var checkedUrlsFile = File(outputFolder + '\\checked.txt').openWrite();
  for (var checkedUrl in checkedUrls) {
    checkedUrlsFile.write("- ${checkedUrl.url}\r\n");
  }
  checkedUrlsFile.close();

  // Ignored by ROBOT URLs
  List<Destination> deniedByRobotsUrls = result.destinations
      .where((destination) => destination.wasDeniedByRobotsTxt)
      .toList(growable: false);
  deniedByRobotsUrls.sort((a, b) => a.url.compareTo(b.url));

  var deniedByRobotsFile = File(outputFolder + '\\denied_by_tobots.txt').openWrite();
  for (var deniedByRobotsUrl in deniedByRobotsUrls) {
    deniedByRobotsFile.write("- ${deniedByRobotsUrl.url}\r\n");
  }
  deniedByRobotsFile.close();

  // Broken and Warning URLs
  Set<Link> links = result.links;
  List<Link> brokenAndWarningLinks = links
      .where((link) =>
          !link.destination.isUnsupportedScheme &&
          !link.wasSkipped &&
          (link.destination.isInvalid ||
              link.destination.wasTried &&
                  (link.destination.isBroken || link.hasWarning)))
      .toList(growable: false);

  List<Uri> sourceBrokenAndWarningUris =
    brokenAndWarningLinks.map((link) => link.origin.uri).toSet().toList(growable: false);
  sourceBrokenAndWarningUris.sort((a, b) => a.toString().compareTo(b.toString()));
  
  var brokenAndWarningUrlsFile = File(outputFolder + '\\broken_warning.txt').openWrite();
  for (var uri in sourceBrokenAndWarningUris) {
      generateFileData(brokenAndWarningUrlsFile, uri, brokenAndWarningLinks, false);
  }
  brokenAndWarningUrlsFile.close();

  // Error URLs
  List<Link> brokenLinks = links
      .where((link) =>
          !link.destination.isUnsupportedScheme &&
          !link.wasSkipped &&
          (link.destination.isInvalid ||
              link.destination.wasTried &&
                  (link.destination.isBroken)))
      .toList(growable: false);

  List<Uri> sourceBrokenUris =
    brokenLinks.map((link) => link.origin.uri).toSet().toList(growable: false);
  sourceBrokenUris.sort((a, b) => a.toString().compareTo(b.toString()));
  
  var brokenUrlsFile = File(outputFolder + '\\broken.txt').openWrite();
  for (var uri in sourceBrokenUris) {
      generateFileData(brokenUrlsFile, uri, brokenLinks, false);
  }
  brokenUrlsFile.close();

  // Warning URLs
  List<Link> warningLinks = links
      .where((link) =>
          !link.destination.isUnsupportedScheme &&
          !link.wasSkipped && 
          link.destination.wasTried &&
          link.hasWarning && !link.hasError)
      .toList(growable: false);

  List<Uri> sourceWarningUris =
    warningLinks.map((link) => link.origin.uri).toSet().toList(growable: false);
  sourceWarningUris.sort((a, b) => a.toString().compareTo(b.toString()));
  
  var warningUrlsFile = File(outputFolder + '\\warning.txt').openWrite();
  for (var uri in sourceWarningUris) {
      generateFileData(warningUrlsFile, uri, warningLinks, true);
  }
  warningUrlsFile.close();
}

void generateFileData(IOSink file, Uri uri, List<Link> broken, bool warningOnly) {
    file.write("${uri.toString()}\r\n");
    var links = broken.where((link) => link.origin.uri == uri);
    for (var link in links) {
      if (warningOnly && !link.hasError || !warningOnly) {
        String tag = _buildTagSummary(link);
      
        file.write("--\r\n");
        file.write("- ${link.origin.span.start.line + 1}\r\n");
        file.write("- ${link.origin.span.start.column}\r\n");
        file.write("- ${tag}\r\n");
        file.write("- ${link.destination.url}");
          file.write(link.fragment == null ? "" : '#${link.fragment}');
        file.write("\r\n- " + (link.hasError ? "error" : "warning"));
        file.write("\r\n- " + link.destination.statusDescription);
        file.write(!link.hasError && link.breaksAnchor ? " but missing anchor" : "");
        file.write("\r\n"); 
      }
    }
    file.write("\r\n");
    file.write("\r\n");
}

/// Writes the reports from the perspective of a website writer - which pages
/// reference broken links.
void reportForWriters(CrawlResult result, bool ansiTerm, Stdout stdout) {
  void print(Object message) => stdout.writeln(message);

  print("");

  Set<Link> links = result.links;
  List<Link> broken = links
      .where((link) =>
          !link.destination.isUnsupportedScheme &&
          !link.wasSkipped &&
          (link.destination.isInvalid ||
              link.destination.wasTried &&
                  (link.destination.isBroken || link.hasWarning)))
      .toList(growable: false);

  List<Destination> deniedByRobots = result.destinations
      .where((destination) => destination.wasDeniedByRobotsTxt)
      .toList(growable: false);
  deniedByRobots.sort((a, b) => a.url.compareTo(b.url));

  List<Uri> sourceUris =
      broken.map((link) => link.origin.uri).toSet().toList(growable: false);
  sourceUris.sort((a, b) => a.toString().compareTo(b.toString()));

  TextPen pen;
  if (ansiTerm) {
    pen = TextPen();
  }

  List<Destination> brokenSeeds = result.destinations
      .where((destination) => destination.isSeed && destination.isBroken)
      .toList(growable: false);
  brokenSeeds.sort((a, b) => a.toString().compareTo(b.toString()));

  if (brokenSeeds.isNotEmpty) {
    print("Provided URLs failing:");
    for (var destination in brokenSeeds) {
      if (ansiTerm) {
        pen
            .reset()
            .yellow()
            .text(destination.url)
            .lightGray()
            .text(" (")
            .red()
            .text(destination.statusDescription)
            .lightGray()
            .text(')')
            .normal()
            .print();
      } else {
        print("${destination.url} (${destination.statusDescription})");
      }
    }

    print("");
  }

  if (deniedByRobots.isNotEmpty) {
    print("Access to these URLs denied by robots.txt, "
        "so we couldn't check them:");
    for (var destination in deniedByRobots) {
      if (ansiTerm) {
        pen
            .reset()
            .normal()
            .text("- ")
            .yellow()
            .text(destination.url)
            .normal()
            .print();
      } else {
        print("- ${destination.url}");
      }
    }

    print("");
  }

  // TODO: summarize when there are huge amounts of sourceURIs for a broken link
  // TODO: report invalid links

  for (var uri in sourceUris) {
    if (ansiTerm) {
      printWithAnsi(uri, broken, pen);
    } else {
      printWithoutAnsi(uri, broken, stdout);
    }
  }
}

void printWithAnsi(Uri uri, List<Link> broken, TextPen pen) {
  pen.reset();
  pen.setColor(Color.YELLOW).text(uri.toString()).normal().print();

  var links = broken.where((link) => link.origin.uri == uri);
  for (var link in links) {
    String tag = _buildTagSummary(link);
    pen.reset();
    pen
        .normal()
        .text("- ")
        .lightGray()
        .text("(")
        .normal()
        .text("${link.origin.span.start.line + 1}")
        .lightGray()
        .text(":")
        .normal()
        .text("${link.origin.span.start.column}")
        .lightGray()
        .text(") ")
        .magenta()
        .text(tag)
        .lightGray()
        .text("=> ")
        .normal()
        .text(link.destination.url)
        .lightGray()
        .text(link.fragment == null ? '' : '#${link.fragment}')
        .text(" (")
        .setColor(link.hasError ? Color.RED : Color.YELLOW)
        .text(link.destination.statusDescription)
        .yellow()
        .text(!link.hasError && link.breaksAnchor ? ' but missing anchor' : '')
        .lightGray()
        .text(')')
        .normal()
        .print();

    if (link.destination.isRedirected) {
      print("  - redirect path:");
      String current = link.destination.url;
      for (var redirect in link.destination.redirects) {
        print("    - $current (${redirect.statusCode})");
        current = redirect.url;
      }
      print("    - $current (${link.destination.statusCode})");
    }
  }
  print("");
}

void printWithoutAnsi(Uri uri, List<Link> broken, Stdout stdout) {
  // Redirect output to injected [stdout] for better testing.
  void print(Object message) => stdout.writeln(message);

  print(uri);

  var links = broken.where((link) => link.origin.uri == uri);
  for (var link in links) {
    String tag = _buildTagSummary(link);
    print("- (${link.origin.span.start.line + 1}"
        ":${link.origin.span.start.column}) "
        "$tag"
        "=> ${link.destination.url}"
        "${link.fragment == null ? '' : '#' + link.fragment} "
        "(${link.destination.statusDescription}"
        "${!link.destination.isBroken && link.breaksAnchor ? ' but missing anchor' : ''}"
        ")");
    if (link.destination.isRedirected) {
      print("  - redirect path:");
      String current = link.destination.url;
      for (var redirect in link.destination.redirects) {
        print("    - $current (${redirect.statusCode})");
        current = redirect.url;
      }
      print("    - $current (${link.destination.statusCode})");
    }
  }
  print("");
}

String _buildTagSummary(Link link) {
  String tag = "";
  if (link.origin.tagName == 'a') {
    const maxLength = 10;
    var text = link.origin.text.replaceAll("\n", " ").trim();
    int length = text.length;
    if (length > 0) {
      if (length <= maxLength) {
        tag = "'$text' ";
      } else {
        tag = "'${text.substring(0, min(length, maxLength - 2))}..' ";
      }
    }
  } else if (link.origin.uri.path.endsWith(".css") &&
      link.origin.tagName == "url") {
    tag = "url(...) ";
  } else {
    tag = "<${link.origin.tagName}> ";
  }
  return tag;
}
