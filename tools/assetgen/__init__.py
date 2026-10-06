"""Procedural asset generator for Glade Quest.

Every image and sound in ``assets/`` is produced by this package from code:
pixel art is authored as text grids (sprites) or drawn procedurally (tiles),
and audio is synthesised with numpy. Output is deterministic, so re-running
the generator yields byte-identical files.
"""
