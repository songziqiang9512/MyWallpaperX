// Shared author script for RF03 VM, Swift admission and scene fixtures.
// Scenario numbers are test inputs, never product routing keys.
function query() {
    const playing = thisLayer.isPlaying();
    if (typeof playing !== 'boolean') throw new Error('isPlaying must return boolean');
    return playing;
}
export function init(value) {
    if (value === 101) { thisLayer.pause(); query(); }
    if (value === 102) {
        thisLayer.stop();
        if (query()) throw new Error('stop must read false in its callback');
    }
    if (value === 103) { thisLayer.stop(); thisLayer.play(); query(); }
    return value;
}
export function update(value) {
    if (thisLayer.id !== 42) throw new Error('fixture must use its real layer handle');
    switch (value) {
    case 1: thisLayer.play(); break;
    case 2: thisLayer.pause(); break;
    case 3: thisLayer.stop(); break;
    case 4: query(); break;
    case 5:
        thisLayer.stop();
        if (query()) throw new Error('stop must read false in its callback');
        break;
    case 6: thisLayer.pause(); query(); break;
    case 7: thisLayer.stop(); thisLayer.play(); query(); break;
    case 8: thisLayer.emitParticles(1); break; // Explicitly unsupported first slice.
    case 9: thisLayer.stop(); throw new Error('reject-this-owner-after-stop');
    }
    return value;
}
