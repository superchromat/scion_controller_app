// signal_colors.dart — the colours that identify a stage of the signal path.
//
// Both are sampled from the SCION front/rear panel artwork, so the app and the
// hardware use the same yellow for the sends and the same blue for the return.

import 'package:flutter/material.dart';

/// The send path: the three analog sends.
///
/// Used for the "Sends" section on the System Overview diagram, the send
/// columns of the Mixer matrix and the Send entries in the nav rail. All of them read this constant so a send
/// cannot end up amber on one page and something else on the other.
const Color kSendSignalColor = Color(0xFFDEB53D);

/// The return path: the capture return and the HDMI out.
///
/// The System Overview marks its "Out" and "Return" sections with this, and
/// the Mixer's Return column and the nav rail's Return entry match. Out shares the colour because it is the
/// same end of the chain, not because it is a return.
const Color kReturnSignalColor = Color(0xFF4091DF);
