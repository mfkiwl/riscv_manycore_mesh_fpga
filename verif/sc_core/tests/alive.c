#define VGA_MEM_BASE 0x00FF0000
#include "fabric_defines.h"
#include "big_core_defines.h"
#include "graphic_vga.h"

int main()  {  
    int x,y,z;  
    x = 2;  
    y = 3;  
    z = x+y;  

rvc_printf("HI\n");
//rvc_printf("THIS IS POC FOR DANIEL\n");
//rvc_printf("NEXT LINE AGAIN\n");
//rvc_printf("A REALLY LONG LINE - I WANT TO SEE IF THE PRINT KNOWS HOW TO MOVE TO THE NEXT LINE ALL BY IT SELF \n");

}  // main()
