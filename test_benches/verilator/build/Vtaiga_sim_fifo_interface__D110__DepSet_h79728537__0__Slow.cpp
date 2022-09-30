// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtaiga_sim.h for the primary calling header

#include "verilated.h"

#include "Vtaiga_sim_fifo_interface__D110.h"

VL_ATTR_COLD void Vtaiga_sim_fifo_interface__D110___ctor_var_reset(Vtaiga_sim_fifo_interface__D110* vlSelf) {
    if (false && vlSelf) {}  // Prevent unused
    Vtaiga_sim__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+                  Vtaiga_sim_fifo_interface__D110___ctor_var_reset\n"); );
    // Body
    vlSelf->pop = VL_RAND_RESET_I(1);
    VL_RAND_RESET_W(272, vlSelf->data_out);
    vlSelf->valid = VL_RAND_RESET_I(1);
    vlSelf->potential_push = VL_RAND_RESET_I(1);
}
