use std::check::assert;
use std::array;
use std::math::fp2::Fp2;
use std::math::fp2::add_ext;
use std::math::fp2::sub_ext;
use std::math::fp2::mul_ext;
use std::math::fp2::inv_ext;
use std::math::fp2::eval_ext;
use std::math::fp2::unpack_ext_array;
use std::math::fp2::next_ext;
use std::math::fp2::from_base;
use std::math::fp2::needs_extension;
use std::math::fp2::fp2_from_array;
use std::math::fp2::constrain_eq_ext;
use std::protocols::fingerprint::fingerprint_with_id;
use std::math::fp2::required_extension_size;
use std::prover::eval;

/// Sends the tuple (id, tuple...) to the bus by adding
/// `multiplicity / (beta - fingerprint(id, tuple...))` to `acc`
/// It is the callers responsibility to properly constrain the multiplicity (e.g. constrain
/// it to be boolean) if needed.
///
/// # Arguments:
/// - id: Interaction Id
/// - tuple: An array of columns to be sent to the bus
/// - multiplicity: The multiplicity which shows how many times a column will be sent
let bus_interaction: expr, expr[], expr -> () = constr |id, tuple, multiplicity| {

    std::check::assert(required_extension_size() <= 2, || "Invalid extension size");

    // Alpha is used to compress the LHS and RHS arrays.
    let alpha = fp2_from_array(array::new(required_extension_size(), |i| challenge(0, i + 1)));
    // Beta is used to update the accumulator.
    let beta = fp2_from_array(array::new(required_extension_size(), |i| challenge(0, i + 3)));

    // Implemented as: folded = (beta - fingerprint(id, tuple...));
    let folded = sub_ext(beta, fingerprint_with_id(id, tuple, alpha));
    let folded_next = next_ext(folded);

    let m_ext = from_base(multiplicity);
    let m_ext_next = next_ext(m_ext);

    let acc = array::new(required_extension_size(), |i| std::prover::new_witness_col_at_stage("acc", 1));
    let acc_ext = fp2_from_array(acc);
    let next_acc = next_ext(acc_ext);

    let is_first: col = std::well_known::is_first;
    let is_first_next = from_base(is_first');

    // Update rule:
    // acc' =  acc * (1 - is_first') + multiplicity' / folded'
    // or equivalently:
    // folded' * (acc' - acc * (1 - is_first')) - multiplicity' = 0
    let update_expr = sub_ext(
        mul_ext(folded_next, sub_ext(next_acc, mul_ext(acc_ext, sub_ext(from_base(1), is_first_next)))), m_ext_next
    );
    
    constrain_eq_ext(update_expr, from_base(0));

    // In the extension field, we need a prover function for the accumulator.
    if needs_extension() {
        // TODO: Helper columns, because we can't access the previous row in hints
        let acc_next_col = std::array::map(acc, |_| std::prover::new_witness_col_at_stage("acc_next", 1));
        query |i| {
            let _ = std::array::zip(
                acc_next_col,
                compute_next_z(is_first, id, tuple, multiplicity, acc_ext, alpha, beta),
                |acc_next, hint_val| std::prover::provide_value(acc_next, i, hint_val)
            );
        };
        std::array::zip(acc, acc_next_col, |acc_col, acc_next| {
            acc_col' = acc_next
        });
    } else {
    }
};

/// Compute acc' = acc * (1 - is_first') + multiplicity' / fingerprint(id, tuple...),
/// using extension field arithmetic.
/// This is intended to be used as a hint in the extension field case; for the base case
/// automatic witgen is smart enough to figure out the value of the accumulator.
let compute_next_z: expr, expr, expr[], expr, Fp2<expr>, Fp2<expr>, Fp2<expr> -> fe[] = query |is_first, id, tuple, multiplicity, acc, alpha, beta| {
    // Implemented as: folded = (beta - fingerprint(id, tuple...));
    // `multiplicity / (beta - fingerprint(id, tuple...))` to `acc`
    let folded = sub_ext(beta, fingerprint_with_id(id, tuple, alpha));
    let folded_next = next_ext(folded);

    let m_ext = from_base(multiplicity);
    let m_ext_next = next_ext(m_ext);

    let is_first_next = eval(is_first');
    let current_acc = if is_first_next == 1 {from_base(0)} else {eval_ext(acc)};
    
    // acc' = current_acc + multiplicity' / folded'
    let res = add_ext(
        current_acc,
        mul_ext(eval_ext(m_ext_next), inv_ext(eval_ext(folded_next)))
    );

    unpack_ext_array(res)
};

/// Convenience function for bus interaction to send columns
let bus_send: expr, expr[], expr -> () = constr |id, tuple, multiplicity| {
    bus_interaction(id, tuple, multiplicity);
};

/// Convenience function for bus interaction to receive columns
let bus_receive: expr, expr[], expr -> () = constr |id, tuple, multiplicity| {
    bus_interaction(id, tuple, -1 * multiplicity);
};