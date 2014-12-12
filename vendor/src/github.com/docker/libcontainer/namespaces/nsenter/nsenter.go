// +build ignore

package nsenter

/*
__attribute__((constructor)) init() {
	nsenter();
}
*/
import "C"
