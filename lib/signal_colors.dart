// signal_colors.dart — the colours that identify a stage of the signal path.

import 'package:flutter/material.dart';

/// The send path: the three analog sends.
///
/// Used for the "Sends" section on the System Overview diagram and for the
/// send columns of the Mixer matrix. Both pages read this constant so a send
/// cannot end up amber on one page and something else on the other.
const Color kSendSignalColor = Color(0xFFF8BA00);

/// The return path: the capture return and the HDMI out.
///
/// The System Overview marks its "Out" and "Return" sections with this, and
/// the Mixer's Return column matches. Out shares the colour because it is the
/// same end of the chain, not because it is a return.
const Color kReturnSignalColor = Color(0xFF49A0F8);
