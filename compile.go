package main

import (
	"github.com/tdewolff/minify"
	"github.com/tdewolff/minify/html"
	"encoding/json"
	"html/template"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var (
	codelabFolder = "learnings/"
)

type Sources struct {
	GoogleDocs []string `json:"googleDocs"`
}

type Codelab struct {
	Environment string    `json:"environment"`
	Updated     time.Time `json:"Updated"`
	Id          string    `json:"id"`
	Duration    int64     `json:"duration"`
	Title       string    `json:"title"`
	Author      string    `json:"author"`
	Summary     string    `json:"summary"`
	Theme       string    `json:"theme"`
	Category    []string  `json:"category"` // should always be cloud
	Tags        []string  `json:"tags"`     // should contain the key technology
	Feedback    string    `json:"feedback"`
	Url         string    `json:"url"`
}

type TemplateVariables struct {
	Technologies []string
	Mappings     map[string][]*Codelab
	Codelabs    []*Codelab
}

func main() {
	log.Print("Reading in configuration file")
	data, err := ioutil.ReadFile("./sources.json")
	if err != nil {
		log.Fatal(err)
	}

	log.Print("Parsing configuration")
	sources := Sources{}
	if err := json.Unmarshal(data, &sources); err != nil {
		log.Fatal(err)
	}

	log.Print("Cleaning any past build")
	os.RemoveAll("build")

	log.Print("Creating build directory")
	os.Mkdir("build", 0777)

	log.Print("Building claats for gdoc sources")
	if err := buildGDocs(sources.GoogleDocs); err != nil {
		log.Fatal(err)
	}

	log.Print("Building landing page")
	if err := buildLanding(); err != nil {
		log.Fatal(err)
	}

	log.Print("Adding statics")
	if err := copyStatics(); err != nil {
		log.Fatal(err)
	}
}

func copyStatics() error {
	dirs, err := filepath.Glob("statics/*")
	if err != nil {
		return err
	}

	for _, dir := range dirs {
		cmd := exec.Command("cp", "-R", dir, "build/")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Start(); err != nil {
			return err
		}

		if err := cmd.Wait(); err != nil {
			return err
		}
	}
	return nil
}

func buildLanding() error {
	codelabs, err := getCodelabs()
	if err != nil {
		return err
	}

	// Create our heirarchy
	mappings := make(map[string][]*Codelab)
	for _, codelab := range codelabs {
		for _, tech := range codelab.Tags {
			tech = strings.ToLower(tech)
			mappings[tech] = append(mappings[tech], codelab)
		}
	}

	// get list of technologies currently in use
	technologies := make([]string, 0)
	for key, _ := range mappings {
		technologies = append(technologies, key)
	}

	// Load templates
	files, err := filepath.Glob("templates/*")
	templates, err := compileTemplates(files...)
	if err != nil {
		return err
	}

	// Create output file
	f, err := os.Create("build/index.html")
	if err != nil {
		return err
	}

	// Render template
	tv := TemplateVariables{
		Technologies: technologies,
		Mappings:     mappings,
		Codelabs:    codelabs,
	}
	if err := templates.ExecuteTemplate(f, "index", &tv); err != nil {
		return err
	}

	return nil

}

func getCodelabs() ([]*Codelab, error) {
	files, err := filepath.Glob("build/" + codelabFolder + "*/codelab.json")
	if err != nil {
		return nil, err
	}

	codelabs := make([]*Codelab, 0, 10)
	for _, file := range files {
		bytes, err := ioutil.ReadFile(file)
		if err != nil {
			return nil, err
		}
		codelab := Codelab{}
		if err := json.Unmarshal(bytes, &codelab); err != nil {
			return nil, err
		}
		codelab.Url = codelabFolder + codelab.Url
		codelabs = append(codelabs, &codelab)
	}
	return codelabs, nil
}

func buildGDocs(gdocs []string) error {
	for _, gdoc := range gdocs {
		log.Printf("Building claat for gdoc: %s\n", gdoc)
		cmd := exec.Command("claat",
			"export",
			"-f", "html",
			"-ga", "UA-88560603-1",
			"-o", "build/" + codelabFolder,
			gdoc)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Start(); err != nil {
			return err
		}
		if err := cmd.Wait(); err != nil {
			return err
		}
	}
	return nil
}

func compileTemplates(filenames ...string) (*template.Template, error) {
    m := minify.New()
    m.AddFunc("text/html", html.Minify)

    var tmpl *template.Template
    for _, filename := range filenames {
        name := filepath.Base(filename)
        if tmpl == nil {
            tmpl = template.New(name)
        } else {
            tmpl = tmpl.New(name)
        }

        b, err := ioutil.ReadFile(filename)
        if err != nil {
            return nil, err
        }

        mb, err := m.Bytes("text/html", b)
        if err != nil {
            return nil, err
        }
        tmpl.Parse(string(mb))
    }
    return tmpl, nil
}

