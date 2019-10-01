package main

import (
	"github.com/hknutzen/Netspoc/go/pkg/pass1"
	"os"
)

func main() {
	pass1.ImportFromPerl()
	pass1.MarkSecondaryRules()
	pass1.RulesDistribution()
	pass1.PrintCode()
	os.Exit(pass1.ErrorCounter)
}
