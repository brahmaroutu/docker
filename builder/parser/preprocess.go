package parser

import (
	"errors"
	"strings"
)

type Block struct {
	Condition   *Node
	Statements  []*Node
	Ifstatement *IfStructure
	Next        *Block
}

type IfStructure struct {
	Ifblock     *Block
	Elsifblocks []*Block
	Elseblock   *Block
}

func pop(dockerfile *[]*Node) *Node {
	retValue := (*dockerfile)[0]
	*dockerfile = (*dockerfile)[1:]
	return retValue
}

func processIf(dockerfile *[]*Node) (*Block, error) {
	var err error
	curBlock := &Block{&Node{}, []*Node{}, &IfStructure{}, nil}

	curBlock.Ifstatement.Ifblock, err = ReadBlock(dockerfile, true)
	if err != nil {
		return nil, err
	}
	for len(*dockerfile) > 0 {
		n := (*dockerfile)[0]
		if strings.ToUpper(n.Value) == "ELSIF" {
			node := pop(dockerfile)
			newBlock, err := ReadBlock(dockerfile, true)
			if err != nil {
				return nil, err
			}
			newBlock.Condition = node
			curBlock.Ifstatement.Elsifblocks = append(curBlock.Ifstatement.Elsifblocks, newBlock)
		}
		if strings.ToUpper(n.Value) == "ELSE" {
			pop(dockerfile)
			curBlock.Ifstatement.Elseblock, err = ReadBlock(dockerfile, true)
			if err != nil {
				return nil, err
			}
		}
		if strings.ToUpper(n.Value) == "ENDIF" {
			return curBlock, nil
		}
	}
	return curBlock, nil
}

func ReadBlock(dockerfile *[]*Node, insideIf bool) (*Block, error) {
	BlockMarker := map[string]bool{
		"ELSIF": true,
		"ELSE":  true,
		"ENDIF": true,
	}

	if !insideIf && BlockMarker[((*dockerfile)[0]).Value] {
		return nil, errors.New("Invalid Block Statment")
	}

	block := &Block{}
	root := block

	for len(*dockerfile) > 0 {
		node := (*dockerfile)[0]
		if BlockMarker[strings.ToUpper(node.Value)] {
			//		time.Sleep(1000 * time.Millisecond)
			return root, nil
		}

		if strings.ToUpper(node.Value) == "IF" {
			node = pop(dockerfile)
			newBlock, err := processIf(dockerfile)
			if err != nil {
				return root, nil
			}
			newBlock.Condition = node
			block.Next = newBlock
			block = &Block{}
			newBlock.Next = block
		} else {
			block.Statements = append(block.Statements, node)
		}
		//		time.Sleep(1000 * time.Millisecond)
		if len(*dockerfile) == 0 {
			return root, errors.New("End Of Stream reached, no end of block statement found")
		}
		node = pop(dockerfile)
	}
	return root, nil
}
