package main

/*
=head1 NAME

add-to-netspoc - Augment one or more objects in netspoc files

=head1 SYNOPSIS

add-to-netspoc [options] FILE|DIR PAIR ...

=head1 DESCRIPTION

This program reads a netspoc configuration and one or more
PAIRS. It augments given object by specified new object in
each file. Changes are done in place, no backup files are created. But
only changed files are touched.

=head1 PAIR

A PAIR is a tuple of typed names "type1:NAME1" "type2:NAME2".
Occurences of "type1:NAME1" are searched and
replaced by "type1:NAME1, type2:NAME2".
Changes are applied only in group definitions and
in implicit groups inside rules, i.e. after "user =", "src =", "dst = ".
Multiple PAIRS can be applied in a single run of add-to-netspoc.

The following types can be used in PAIRS:
B<network host interface any group>.

=head1 OPTIONS

=over 4

=item B<-f> file

Read PAIRS from file.

=item B<-q>

Quiet, don't print status messages.

=item B<-help>

Prints a brief help message and exits.

=back

=head1 COPYRIGHT AND DISCLAIMER

(c) 2020 by Heinz Knutzen <heinz.knutzengooglemail.com>

http://hknutzen.github.com/Netspoc

This program is free software; you can redistribute it &&/|| modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, ||
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY || FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
*/

import (
	"fmt"
	"github.com/hknutzen/Netspoc/go/pkg/abort"
	"github.com/hknutzen/Netspoc/go/pkg/conf"
	"github.com/hknutzen/Netspoc/go/pkg/diag"
	"github.com/hknutzen/Netspoc/go/pkg/filetree"
	"github.com/spf13/pflag"
	"io/ioutil"
	"os"
	"regexp"
	"strings"
)

var validType = map[string]bool{
	"network":   true,
	"host":      true,
	"interface": true,
	"any":       true,
	"group":     true,
	"area":      true,
}

var addTo = make(map[string]string)

func checkName(typedName string) {
	pair := strings.SplitN(typedName, ":", 2)
	if len(pair) != 2 {
		abort.Msg("Missing type in %s", typedName)
	}
	if !validType[pair[0]] {
		abort.Msg("Can't use type in %s", typedName)
	}
	re := regexp.MustCompile(`[^-\w\p{L}.:\@\/\[\]]`)
	if m := re.FindStringSubmatch(pair[1]); m != nil {
		abort.Msg("Invalid character '%s' in %s", m[0], typedName)
	}
}

// Fill addTo with old => new pairs.
func setupAddTo(old, new string) {
	checkName(old)
	checkName(new)
	addTo[old] = new
}

// Find occurrence of typed name in list of objects:
// - group:<name> = <typed name>, ... <typed name>
// - src =
// - dst =
// but ignore typed name in definition:
// - <typed name> =
func process(input string) (int, string) {
	changed := 0
	inList := false
	var copy strings.Builder
	copy.Grow(len(input))
	substDone := false

	comment := regexp.MustCompile(`^\s*[#].*\n`)
	typedName := regexp.MustCompile(`^(\s*)(\w+:[-\w\p{L}.\@:]+)`)
	extension := regexp.MustCompile(`^\[(?:auto|all)\]`)
	commaSemiEOL := regexp.MustCompile(`^((?:[ \t]*[,;])?)([ \t]*(?:[#].*)?)(?:\n|$)`)
	comma := regexp.MustCompile(`^\s*,`)
	startAuto := regexp.MustCompile(`^\s*\w+:\[`)
	managedAuto := regexp.MustCompile(`^\s*managed\s*&`)
	ipAuto := regexp.MustCompile(`^\s*ip\s*=\s*[a-f:/0-9.]+\s*&`)
	endAuto := regexp.MustCompile(`^\s*\]`)
	negation := regexp.MustCompile(`^\s*[!]`)
	intersection := regexp.MustCompile(`^\s*[&]`)
	startGroup := regexp.MustCompile(`^.*?(?:src|dst|user|group:[-\w\p{L}]+)`)
	equalSign := regexp.MustCompile(`^\s*=[ \t]*`)
	restToEOL := regexp.MustCompile(`^(?:.*\n|.+$)`)

	// Match pattern in input and skip matched pattern.
	match := func(re *regexp.Regexp) []string {
		matches := re.FindStringSubmatch(input)
		if matches == nil {
			return nil
		}
		skip := len(matches[0])
		input = input[skip:]
		return matches
	}

	for {
		if m := match(comment); m != nil {
			// Ignore comment.
			copy.WriteString(m[0])
		} else if inList {
			// Find next "type:name".
			if m := match(typedName); m != nil {
				space := m[1]
				object := m[2]
				if m := match(extension); m != nil {
					object += m[0]
				}
				new := addTo[object]
				if new == "" {
					copy.WriteString(space)
					copy.WriteString(object)
					substDone = false
					continue
				}
				changed++
				substDone = true
				copy.WriteString(space)

				// Check if current line has only one entry, possibly
				// preceeded by start of list.
				var prefix string
				processed := copy.String()
				idx := strings.LastIndex(processed, "\n")
				if idx != -1 {
					prefix = processed[idx+1:]
				} else {
					prefix = processed
				}
				var m []string
				re := regexp.MustCompile(
					`^(?:[ \t]*[-\w\p{L}:]+[ \t]*=)?[ \t]*$`)
				if re.MatchString(prefix) {
					m = match(commaSemiEOL)
				}
				if m != nil {
					// Add new entry to separate line with same indentation.
					delim, comment := m[1], m[2]
					indent := strings.Repeat(" ", len([]rune(prefix)))
					copy.WriteString(object)
					copy.WriteString(",")
					copy.WriteString(comment)
					copy.WriteString("\n")
					copy.WriteString(indent)
					copy.WriteString(new)
					copy.WriteString(delim)
					copy.WriteString("\n")
				} else {
					// Add new entry on same line separated by white space.
					copy.WriteString(object)
					copy.WriteString(", ")
					copy.WriteString(new)
				}
			} else {
				// Check if list continues.
				inList = false
				for _, re := range []*regexp.Regexp{
					startAuto, managedAuto, ipAuto, endAuto,
					negation, intersection, comma} {
					if m := match(re); m != nil {
						inList = true
						copy.WriteString(m[0])
						if substDone && re == intersection {
							fmt.Fprintln(os.Stderr,
								"Warning: Substituted in intersection")
						}
						break
					}
				}
			}
		} else if m := match(startGroup); m != nil {
			// Find start of group.
			copy.WriteString(m[0])

			// Find equal sign.
			if m = match(equalSign); m != nil {
				copy.WriteString(m[0])
				inList = true
			}
		} else if m := match(restToEOL); m != nil {
			// Ignore rest of line if nothing matches.
			copy.WriteString(m[0])
		} else {
			// Terminate if everything has been processed.
			break
		}
	}
	return changed, copy.String()
}

func processInput(input *filetree.Context) {
	count, copy := process(input.Data)
	if count == 0 {
		return
	}
	path := input.Path
	diag.Info("%d changes in %s", count, path)
	err := os.Remove(path)
	if err != nil {
		abort.Msg("Can't remove %s: %s", path, err)
	}
	file, err := os.Create(path)
	if err != nil {
		abort.Msg("Can't create %s: %s", path, err)
	}
	_, err = file.WriteString(copy)
	if err != nil {
		abort.Msg("Can't write to %s: %s", path, err)
	}
	file.Close()
}

func setupPairs(pairs []string) {
	for len(pairs) > 0 {
		old := pairs[0]
		if len(pairs) == 1 {
			abort.Msg("Missing 2nd. element for '%s'", old)
		}
		new := pairs[1]
		pairs = pairs[2:]
		setupAddTo(old, new)
	}
}

func readPairs(path string) {
	bytes, err := ioutil.ReadFile(path)
	if err != nil {
		abort.Msg("Can't %s", err)
	}
	pairs := strings.Fields(string(bytes))
	if len(pairs) == 0 {
		abort.Msg("Missing pairs in %s", path)
	}
	setupPairs(pairs)
}

func main() {

	// Setup custom usage function.
	pflag.Usage = func() {
		fmt.Fprintf(os.Stderr,
			"Usage: %s [options] FILE|DIR PAIR ...\n", os.Args[0])
		pflag.PrintDefaults()
	}

	// Command line flags
	quiet := pflag.BoolP("quiet", "q", false, "Don't show number of changes")
	fromFile := pflag.StringP("file", "f", "", "Read pairs from file")
	pflag.Parse()

	// Argument processing
	args := pflag.Args()
	if len(args) == 0 {
		pflag.Usage()
		os.Exit(1)
	}
	path := args[0]

	// Initialize search/add pairs.
	if *fromFile != "" {
		readPairs(*fromFile)
	}
	if len(args) > 1 {
		setupPairs(args[1:])
	}

	// Initialize config, especially "ignoreFiles'.
	dummyArgs := []string{fmt.Sprintf("--verbose=%v", !*quiet)}
	conf.ConfigFromArgsAndFile(dummyArgs, path)

	// Do substitution.
	filetree.Walk(path, processInput)
}
