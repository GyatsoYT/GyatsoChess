from defs import *
from nnue import *
from endgame import *
from position import *

def evaluate(pos: Position) -> Value:
    '''Main evaluation function.'''

    if pos.is_material_draw:
        return 0

    try:
        return mop_up_evaluation(pos)
    except NoMopUpEvaluation:
        pass
    
    us = pos.side
    ours = pos.accumulator[us]        # Our accumulation
    theirs = pos.accumulator[not us]  # Their accumulation

    # Hidden layer forward propogation
    v = OUTPUT_BIAS * QUANTIZATION_PRECISION_IN + sum([
        + (our_activation * our_weight if our_activation > 0 else 0)
        + (their_activation * their_weight if their_activation > 0 else 0)
        for our_activation, their_activation, our_weight, their_weight
        in zip(ours, theirs, OUR_HIDDEN_WEIGHTS, THEIR_HIDDEN_WEIGHTS)
    ])
    
    return Value(v / QUANTIZATION_PRECISION_IN / QUANTIZATION_PRECISION_OUT)
