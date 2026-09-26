package config

import (
	"fmt"
	"reflect"
	"strings"

	"go.yaml.in/yaml/v3"
)

// unknownKeys returns the dotted path of every YAML key that has no matching
// field in v, so errors can name "server.lisen" instead of just "lisen".
func unknownKeys(doc *yaml.Node, v any) []string {
	var out []string
	walkKeys(doc, reflect.TypeOf(v), "", &out)
	return out
}

func walkKeys(n *yaml.Node, t reflect.Type, path string, out *[]string) {
	for t.Kind() == reflect.Pointer {
		t = t.Elem()
	}
	switch {
	case n.Kind == yaml.DocumentNode:
		for _, c := range n.Content {
			walkKeys(c, t, path, out)
		}
	case t.Kind() == reflect.Struct && n.Kind == yaml.MappingNode:
		fields := yamlFields(t)
		for i := 0; i+1 < len(n.Content); i += 2 {
			key := n.Content[i].Value
			p := key
			if path != "" {
				p = path + "." + key
			}
			ft, ok := fields[key]
			if !ok {
				*out = append(*out, p)
				continue
			}
			walkKeys(n.Content[i+1], ft, p, out)
		}
	case t.Kind() == reflect.Slice && n.Kind == yaml.SequenceNode:
		for i, c := range n.Content {
			walkKeys(c, t.Elem(), fmt.Sprintf("%s[%d]", path, i), out)
		}
	}
}

func yamlFields(t reflect.Type) map[string]reflect.Type {
	fields := make(map[string]reflect.Type, t.NumField())
	for i := range t.NumField() {
		f := t.Field(i)
		if !f.IsExported() {
			continue
		}
		name, _, _ := strings.Cut(f.Tag.Get("yaml"), ",")
		if name == "-" {
			continue
		}
		if name == "" {
			name = strings.ToLower(f.Name)
		}
		fields[name] = f.Type
	}
	return fields
}
