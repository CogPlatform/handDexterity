# Hand Dexterity Analysis
A MATLAB-based pipeline for analyzing fine motor behavior during apple grasping tasks, using tracking data from DeepLabCut.

## Table of Contents
- [Experimental Setup & Design](#1-experimental-setup--design)
- [Video Recording](#2-video-recording)
- [Video Tracking](#3-video-tracking)
- [Behavioral Analysis](#4-behavioral-analysis)
- [Installation](#installation)
- [Usage](#usage)
- [Folder Structure](#folder-structure)
- [Output Metrics](#output-metrics)

## 1. Experimental Setup & Design
We used two 7 cm × 7 cm transparent plexiglass plates, fixed 10 mm apart on a custom-built experimental setup. During experiments, an experimenter used a sliding rod to deliver the reward (apple) from behind a barrier into the gap between the two plexiglass plates, ensuring it stopped at a fixed position each time. After the subject grasped the apple, the rod was retracted, the next apple was loaded, and the rod was pushed back to the center of the plexiglass plates. This process repeated until the subject completed approximately 35 grasps; the exact number varied based on the subject’s condition.

## 2. Video Recording
A USB camera was focused on the subject’s hand and recorded the entire session to capture fine motor movements during grasping.

## 3. Video Tracking
The recorded videos were processed with **DeepLabCut** (a deep learning-based pose estimation tool) to generate two CSV files containing 2D (x-y) coordinates:
- Hand keypoint file: Records positions of key joints (thumb and index finger) of the subject’s hand.
- Apparatus/reward file: Records positions of the plexiglass edges and the apple (reward).

## 4. Behavioral Analysis
This MATLAB pipeline uses the two CSV files to:
1. Reconstruct movement trajectories of the hand, experimental apparatus, and apple.
2. Calculate relative positions between the hand and reward/apparatus.
3. Quantify key behavioral metrics (reaction time, error rates) to evaluate fine motor control in subjects.

## Installation
### Prerequisites
- MATLAB R2020b or later (tested on R2020b/R2022a/R2023a)
- No additional MATLAB toolboxes required (uses built-in functions only)
- DeepLabCut (for generating tracking CSV files; optional if using preprocessed data)

### Clone the Repository
```bash
git clone https://github.com/your-username/hand-dexterity-analysis.git
cd hand-dexterity-analysis
```

## Usage
### Step 1: Prepare Data
1. Place your DeepLabCut-generated CSV files in the `example files/` folder (see [Folder Structure](#folder-structure)).
2. Ensure filenames follow the convention:
   - Hand data: `[date]-[subjectID]-hand.csv` (e.g., `06-30-7-hand.csv`)
   - Apple/apparatus data: `[date]-[subjectID]-apple.csv` (e.g., `06-30-7-apple.csv`)

### Step 2: Run the Analysis
1. Open MATLAB and navigate to the repository folder.
2. Run the main script:
   ```matlab
   % In MATLAB Command Window
   HandDexterity
   ```
3. When prompted, select the folder containing your CSV files (default: `example files/`).
4. The script will:
   - Process all CSV file pairs automatically.
   - Generate Excel output files with quantitative metrics.
   - Plot apple trajectory visualizations (optional).

### Step 3: View Results
- Excel files (per subject) are saved to the selected data folder.
- MAT files (detailed raw results) are saved alongside the Excel files (optional).

## Folder Structure
```
hand-dexterity-analysis/
├── example files/          # Sample input CSV files (DeepLabCut tracking data)
│   ├── 06-30-7-apple.csv
│   ├── 06-30-7-hand.csv
│   └── ... (additional CSV pairs)
├── HandDexterity.m         # Main analysis script (core pipeline)
├── README.md               # Project documentation
└── output/                 # Auto-generated folder for results (created at runtime)
    ├── 06-30-7.xlsx        # Quantitative metrics for subject 7
    ├── 06-30-7.mat         # Raw analysis results (MAT file)
    └── ...
```

## Output Metrics
The Excel output files contain the following key metrics (rounded to 2 decimal places):
| Metric | Description |
|--------|-------------|
| `slitErrorRate` | Error rate of hand hitting the plexiglass slit (slow movement at slit edge) |
| `wanderErrorRate` | Error rate of multiple re-grasp attempts (poor movement stability) |
| `dropRate` | Rate of apple dropping during grasping |
| `fetchTime(Valid trials:ms)` | Mean reaction time for valid grasps (milliseconds) |
| `distance(Apple-Edge:mm)` | Mean distance between apple and plexiglass edge (millimeters) |

---
