/*  
 * Jakefile
 * StropheCappuccino
 *    
 * Copyright (C) 2010 Antoine Mercadal <antoine.mercadal@inframonde.eu>
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

require("./common.jake")

var ENV = require("system").env,
    FILE = require("file"),
	OS = require("os"),
	JAKE = require("jake"),
    task = JAKE.task,
    CLEAN = require("jake/clean").CLEAN,
    FileList = JAKE.FileList,
    stream = require("narwhal/term").stream,
    framework = require("cappuccino/jake").framework,
    configuration = ENV["CONFIG"] || ENV["CONFIGURATION"] || ENV["c"] || "Release";

$DOCUMENTATION_BUILD = FILE.join("Build", "Documentation");

framework ("StropheCappuccino", function(task)
{
    task.setBuildIntermediatesPath(FILE.join("Build", "StropheCappuccino.build", configuration));
    task.setBuildPath(FILE.join("Build", configuration));

    task.setProductName("StropheCappuccino");
    task.setIdentifier("org.archipelproject.strophecappuccino");
    task.setVersion("1.0");
    task.setAuthor("Antoine Mercadal");
    task.setEmail("antoine.mercadal @nospam@ inframonde.eu");
    task.setSummary("StropheCappuccino");
    task.setSources(new FileList("*.j", "StropheCappuccino/*.j"));
    task.setResources(new FileList("Resources/*"));
    task.setInfoPlistPath("Info.plist");

    if (configuration === "Debug")
        task.setCompilerFlags("-DDEBUG -g");
    else
        task.setCompilerFlags("-O");
});

task("build", ["StropheCappuccino"]);

task("debug", function()
{
    ENV["CONFIG"] = "Debug"
    JAKE.subjake(["."], "build", ENV);
});

task("release", function()
{
    ENV["CONFIG"] = "Release"
    JAKE.subjake(["."], "build", ENV);
});

task ("documentation", function()
{
    // try to find a doxygen executable in the PATH;
    var doxygen = executableExists("doxygen");

    // If the Doxygen application is installed on Mac OS X, use that
    if (!doxygen && executableExists("mdfind"))
    {
        var p = OS.popen(["mdfind", "kMDItemContentType == 'com.apple.application-bundle' && kMDItemCFBundleIdentifier == 'org.doxygen'"]);
        if (p.wait() === 0)
        {
            var doxygenApps = p.stdout.read().split("\n");
            if (doxygenApps[0])
                doxygen = FILE.join(doxygenApps[0], "Contents/Resources/doxygen");
        }
    }

    if (doxygen && FILE.exists(doxygen))
    {
        stream.print("\0green(Using " + doxygen + " for doxygen binary.\0)");

        var documentationDir = FILE.join("Doxygen");

        if (OS.system([FILE.join(documentationDir, "make_headers.sh")]))
            OS.exit(1); //rake abort if ($? != 0)

        if (!OS.system([doxygen, FILE.join(documentationDir, "StropheCappuccino.doxygen")]))
        {
            rm_rf($DOCUMENTATION_BUILD);
            // mv("debug.txt", FILE.join("Documentation", "debug.txt"));
            mv("Documentation", $DOCUMENTATION_BUILD);
        }

        OS.system(["ruby", FILE.join(documentationDir, "cleanup_headers")]);
    }
    else
        stream.print("\0yellow(Doxygen not installed, skipping documentation generation.\0)");
});

task("test", function()
{
    var tests = new FileList('Test/*Test.j');
    var cmd = ["ojtest"].concat(tests.items());
    var cmdString = cmd.map(OS.enquote).join(" ");

    var code = OS.system(cmdString);
    if (code !== 0)
        OS.exit(code);
});

task ("default", ["release"]);
task ("docs", ["release", "documentation"]);
task ("all", ["release", "debug", "documentation"]);
