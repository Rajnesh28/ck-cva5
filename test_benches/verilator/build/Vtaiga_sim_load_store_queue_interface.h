// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtaiga_sim.h for the primary calling header

#ifndef VERILATED_VTAIGA_SIM_LOAD_STORE_QUEUE_INTERFACE_H_
#define VERILATED_VTAIGA_SIM_LOAD_STORE_QUEUE_INTERFACE_H_  // guard

#include "verilated.h"

class Vtaiga_sim__Syms;

class Vtaiga_sim_load_store_queue_interface final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    VlWide<5>/*141:0*/ transaction_out;

    // INTERNAL VARIABLES
    Vtaiga_sim__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtaiga_sim_load_store_queue_interface(Vtaiga_sim__Syms* symsp, const char* name);
    ~Vtaiga_sim_load_store_queue_interface();
    VL_UNCOPYABLE(Vtaiga_sim_load_store_queue_interface);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
} VL_ATTR_ALIGNED(VL_CACHE_LINE_BYTES);


#endif  // guard
