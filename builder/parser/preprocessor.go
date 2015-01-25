package parser

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func PreProcess(dockerfile *[]*Node) ([]Node, error) {
	newData := []Node{}
	for len(*dockerfile) > 0 {
		n := pop(dockerfile)
		if strings.ToUpper(n.Value) == "IF" {
			blockdata, err := processIf(dockerfile, n.Next)
			if err != nil {
				return nil, err
			}
			newData = append(newData, blockdata...)
		} else {
			newData = append(newData, *n)
		}
	}

	return newData, nil
}

func evaluateCondition(cond string) (bool, error) {
	args := strings.Split(cond, "==")
	if len(args) != 2 {
		if b, err := strconv.ParseBool(cond); err != nil {
			return false, errors.New(fmt.Sprintf("Aborting build, Invalid condition: (%q) error: %q", cond, err))
		} else {
			return b, nil
		}
	}

	if strings.HasPrefix(args[0], "$") {
		args[0] = os.Getenv(strings.Trim(args[0], "$ "))
	}

	if strings.HasPrefix(args[1], "$") {
		args[1] = os.Getenv(strings.Trim(args[1], "$ "))
	}
	return (strings.Trim(args[0], " ") == strings.Trim(args[1], " ")), nil
}

func pop(dockerfile *[]*Node) *Node {
	retValue := (*dockerfile)[0]
	*dockerfile = (*dockerfile)[1:]
	return retValue
}

func processIf(dockerfile *[]*Node, node *Node) ([]Node, error) {
	if node == nil || node.Value == "" {
		return nil, nil
	}
	if cond, err := evaluateCondition(node.Value); err != nil {
		return nil, err
	} else if cond {
		newBlock, err := readIfBlock(dockerfile)
		skipIfBlock(dockerfile, true)
		n := pop(dockerfile)
		if strings.ToUpper(n.Value) != "ENDIF" {
			return newBlock, errors.New("Did not find ENDIF at the end of the if block")
		}
		return newBlock, err
	} else {
		skipIfBlock(dockerfile, false)
		for len(*dockerfile) > 0 {
			if strings.ToUpper((*dockerfile)[0].Value) == "ELSIF" {
				n := pop(dockerfile)
				if cond, err := evaluateCondition(n.Next.Value); err != nil {
					return nil, err
				} else if cond {
					newBlock, err := readIfBlock(dockerfile)
					skipIfBlock(dockerfile, true)
					n := pop(dockerfile)
					if strings.ToUpper(n.Value) != "ENDIF" {
						return newBlock, errors.New("Did not find ENDIF at the end of the if block")
					}

					return newBlock, err
				} else {
					skipIfBlock(dockerfile, false)
				}
			}
			if strings.ToUpper((*dockerfile)[0].Value) == "ELSE" {
				pop(dockerfile)
				newBlock, err := readIfBlock(dockerfile)
				n := pop(dockerfile)
				if strings.ToUpper(n.Value) != "ENDIF" {
					return newBlock, errors.New("Did not find ENDIF at the end of the if block")
				}
				return newBlock, err
			}
			if strings.ToUpper((*dockerfile)[0].Value) == "ENDIF" {
				pop(dockerfile)
				return nil, nil
			}

		}

		return nil, nil
	}
	return nil, errors.New("Unknow error preprocessing")
}

func readIfBlock(dockerfile *[]*Node) ([]Node, error) {
	BlockMarker := map[string]bool{
		"ELSIF": true,
		"ELSE":  true,
		"ENDIF": true,
	}
	newData := []Node{}
	for len(*dockerfile) > 0 {
		n := (*dockerfile)[0]
		if strings.ToUpper(n.Value) == "IF" {
			pop(dockerfile)
			blockData, err := processIf(dockerfile, n.Next)
			if err != nil {
				return nil, err
			}
			newData = append(newData, blockData...)
			continue
		} else if BlockMarker[strings.ToUpper(n.Value)] {
			return newData, nil
		} else {
			newData = append(newData, *n)
		}
		pop(dockerfile)
	}
	return newData, errors.New("No matching ENDIF")

}

func skipIfBlock(dockerfile *[]*Node, innerIf bool) {
	BlockMarker := map[string]bool{
		"ELSIF": true,
		"ELSE":  true,
		"ENDIF": true,
	}

	for len(*dockerfile) > 0 {
		node := (*dockerfile)[0]
		if (!innerIf && BlockMarker[strings.ToUpper(node.Value)]) ||
			(innerIf && strings.ToUpper(node.Value) == "ENDIF") {
			return
		}

		pop(dockerfile)
		if strings.ToUpper(node.Value) == "IF" {
			skipIfBlock(dockerfile, true)
			pop(dockerfile)
		}
	}
}
