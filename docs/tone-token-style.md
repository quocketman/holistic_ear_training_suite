# Tune Indigo — Tone Token Style Reference

A **tone token** represents one pitch. Its **color encodes the pitch** and its
**vertical position encodes the pitch height**; the horizontal axis is time
(left → right = earlier → later).

Default token look (current):

- **Shape:** circle (a hexagon variant also exists, but circle is the default).
- **Fill:** solid **black**.
- **Outline / ring:** the **pitch color** from the palette below, stroke ≈ **2.5% of the token diameter**.
- **Label:** the **solfège syllable** (`do`, `re`, `mi`, …), centered, **bold** (Source Sans 3), **white**.
- **Active/“sounding” state:** a soft **white radial halo** behind the token, ~1.5× its diameter.

On a white page (print/PDF): black-filled circle, colored ring, white label.

---

## 1. Color palette

The palette is a **12-color wheel indexed by chromatic offset** — the number of
**semitones above the tonic (`do`)**, 0–11. It runs Red → Magenta.

> This exact palette is the shared source of truth across the Assessment Tool
> (Flutter/Dart) and SolfaWhiteboard (Swift). Keep them in sync.

| Offset | Solfège (movable *do*) | Name | Hex |
|:---:|:---|:---|:---|
| 0 | do | Red | `#FF2100` |
| 1 | di / ra | Burnt Orange | `#ED5500` |
| 2 | re | Orange | `#FF8000` |
| 3 | ri / me | Amber | `#FFB000` |
| 4 | mi | Yellow | `#FCE600` |
| 5 | fa | Green | `#00BA00` |
| 6 | fi / se | Teal | `#2498B3` |
| 7 | so (sol) | Blue | `#3F55C7` |
| 8 | si / le | Purple | `#5600DD` |
| 9 | la | Royal Blue | `#0053F9` |
| 10 | li / te | Violet | `#7A1DFF` |
| 11 | ti | Magenta | `#E002C2` |

**Usage notes**

- The offset is relative to the tonic, not absolute pitch. In the key of C, `do` = C = Red; in the key of G, `do` = G = Red. The palette moves with the key (movable *do*).
- The color is applied as the **token ring** (and the label stays white on the black fill). If you fill a shape with the color instead of ringing it, use white or black text for contrast as needed.
- Octaves reuse the same color — a `do` an octave up is still Red; only its vertical position changes (see §2).

---

## 2. Vertical spacing

Pitch maps to the vertical axis: **higher pitch = higher on the page.**

The spacing is defined **relative to the token diameter**, so it scales with
token size. The governing constant is the **chromatic spread = 1.5**:

```
semitone spacing (center-to-center) = token diameter ÷ 1.5  ≈  0.667 × diameter
```

So, per interval, the vertical distance between two tokens' centers:

| Interval | Semitones | Vertical distance (× token diameter) |
|:---|:---:|:---:|
| Half step (e.g. mi→fa) | 1 | 0.67 |
| Whole step (e.g. do→re) | 2 | 1.33 |
| Minor third | 3 | 2.00 |
| Perfect fifth | 7 | 4.67 |
| Octave (do→do) | 12 | 8.00 |

**What “spread = 1.5” means visually:** since a half-step spacing (0.667 × d) is
smaller than one diameter, **adjacent-semitone tokens overlap by ~⅓**. Whole-step
neighbors sit with about ⅓ of a token’s worth of gap between their edges. This
keeps close pitches visually connected without piling up at wide ranges.

**Placement formula** (for a run of notes):

```
y(note) = baseline − (noteOffset − lowestOffset) × (diameter ÷ 1.5)
          (subtract because higher pitch = smaller y / higher up)
```

where `noteOffset` is the note's total chromatic value (offset + 12 × octave),
and `lowestOffset` is the lowest note in the group.

### Concrete numbers (print / PDF sheet)

The letter-size PDF uses a **fixed** token size (no rescaling):

- **Token diameter:** 0.30″ (60 px at 200 dpi)
- **Semitone spacing:** 0.20″ (40 px) — i.e. 0.30″ ÷ 1.5
- **Octave span:** 2.40″ (480 px)
- **Page margins:** 0.75″ all sides
- **Gap between systems (lines of music):** ~2 token diameters (0.60″ / 120 px), with a thin grey separator line centered in the gap
- Systems auto-wrap to fit the printable width and flow onto additional pages (~3 systems/page)

### On-screen behavior

The live editor holds the token size **stable** by sizing as though the pitch
axis is always **at least one octave (12 semitones) tall**. Melodies within an
octave render at one fixed size (no rescaling as notes are added); only
wider-than-octave melodies shrink to fit.
