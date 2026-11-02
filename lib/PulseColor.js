.pragma library

const tealColor = "#2aa198";
const purpleColor = "#a77bd8";
const blueColor = "#3b82f6";
const yellowColor = "#ebcb8b";
const colorPresets = [
    {
        label: "Teal",
        value: tealColor
    },
    {
        label: "Purple",
        value: purpleColor
    },
    {
        label: "Blue",
        value: blueColor
    },
    {
        label: "Yellow",
        value: yellowColor
    }
];

function isPulseColor(value) {
    return /^#[0-9a-fA-F]{6}$/.test(String(value || "").trim());
}

function normalizedPulseColor(value) {
    var color = String(value || "").trim().toLowerCase();
    return isPulseColor(color) ? color : tealColor;
}

function presetForColor(value) {
    var color = normalizedPulseColor(value);
    return color === tealColor || color === purpleColor || color === blueColor || color === yellowColor ? color : "custom";
}
