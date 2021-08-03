import numpy as np
import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import Circle, Ellipse
from matplotlib.collections import PatchCollection

import argparse
import os
import pandas as pd
import re
import json


class ParseError(Exception):
    pass


class LogError(Exception):
    pass


plt.style.use('default')
plt.rcParams['font.size'] = 30
plt.rcParams['axes.labelsize'] = 30
plt.rcParams['axes.labelweight'] = 'bold'
plt.rcParams['xtick.labelsize'] = 20
plt.rcParams['ytick.labelsize'] = 20
plt.rcParams['legend.fontsize'] = 30
plt.rcParams['figure.titlesize'] = 30

argparser = argparse.ArgumentParser()
argparser.add_argument("path", help="Path to a histo file or a directory")
argparser.add_argument(
    "--ratio",
    action="store_true",
    help=
    "Plot operations with disk radius proportionnal to the amount of time spent at this y-ordinate."
)
argparser.add_argument(
    "-R",
    action="store_true",
    help="Recursively follow directories in [path] to find histo files")

args = argparser.parse_args()


def find_dirs(path, rec=False):
    if os.path.isfile(path):
        if rec:
            raise ParseError(f"{path} is not a directory.")
        path = os.path.dirname(path)
    if os.path.isdir(path):
        paths = []
        if rec:
            for (dirpath, _dirnames, filenames) in os.walk(path):
                if "histo" in filenames:
                    paths.append(os.path.join(dirpath, "histo"))
        else:
            if "histo" in os.listdir(path):
                paths.append(os.path.join(path, "histo"))
        return paths
    return []


def read_histo(paths):
    ret = []
    for path in paths:
        print(path)
        with open(path, "r") as histo:
            histo = json.load(histo)
            for fname, bins in histo.items():
                centers, counts = list(
                    zip(*[(item['center'], item['count']) for item in bins]))
                centers = np.exp(
                    np.array(centers)) / 1_000_000  # convert microsec to sec
                histo[fname] = np.array([centers, counts])
            ret.append(histo)
    return ret


cmap = plt.get_cmap("Set1")  # color palette


def legendpoint(color, label):
    # creates an Artist to override legend markers
    return Line2D([0], [0],
                  marker='o',
                  color='w',
                  label=label,
                  markerfacecolor=color,
                  markersize=12)


def get_handles(labels):
    return [legendpoint(cmap(i), label) for i, label in enumerate(labels)]


def set_labels(fig, xlabel, ylabel):
    # set global x and y axis labels over a grid of axis
    bx = fig.add_subplot(111, frameon=False, alpha=0)
    bx.set_yticklabels([])
    bx.set_xticklabels([])
    bx.set_yticks([])
    bx.set_xticks([])
    bx.grid(False)
    bx.set_xlabel(xlabel, labelpad=40)
    bx.set_ylabel(ylabel, labelpad=60)


def ellipses(x, y, w, h=None, rot=0.0, c='b', vmin=None, vmax=None, **kwargs):
    """
    Make a scatter plot of ellipses. 
    Parameters
    ----------
    x, y : scalar or array_like, shape (n, )
        Center of ellipses.
    w, h : scalar or array_like, shape (n, )
        Total length (diameter) of horizontal/vertical axis.
        `h` is set to be equal to `w` by default, ie. circle.
    rot : scalar or array_like, shape (n, )
        Rotation in degrees (anti-clockwise).
    c : color or sequence of color, optional, default : 'b'
        `c` can be a single color format string, or a sequence of color
        specifications of length `N`, or a sequence of `N` numbers to be
        mapped to colors using the `cmap` and `norm` specified via kwargs.
        Note that `c` should not be a single numeric RGB or RGBA sequence
        because that is indistinguishable from an array of values
        to be colormapped. (If you insist, use `color` instead.)
        `c` can be a 2-D array in which the rows are RGB or RGBA, however.
    vmin, vmax : scalar, optional, default: None
        `vmin` and `vmax` are used in conjunction with `norm` to normalize
        luminance data.  If either are `None`, the min and max of the
        color array is used.
    kwargs : `~matplotlib.collections.Collection` properties
        Eg. alpha, edgecolor(ec), facecolor(fc), linewidth(lw), linestyle(ls),
        norm, cmap, transform, etc.
    Returns
    -------
    paths : `~matplotlib.collections.PathCollection`
    Examples
    --------
    a = np.arange(11)
    ellipses(a, a, w=4, h=a, rot=a*30, c=a, alpha=0.5, ec='none')
    plt.colorbar()
    License
    --------
    This code is under [The BSD 3-Clause License]
    (http://opensource.org/licenses/BSD-3-Clause)
    """
    if np.isscalar(c):
        kwargs.setdefault('color', c)
        c = None

    if 'fc' in kwargs:
        kwargs.setdefault('facecolor', kwargs.pop('fc'))
    if 'ec' in kwargs:
        kwargs.setdefault('edgecolor', kwargs.pop('ec'))
    if 'ls' in kwargs:
        kwargs.setdefault('linestyle', kwargs.pop('ls'))
    if 'lw' in kwargs:
        kwargs.setdefault('linewidth', kwargs.pop('lw'))
    # You can set `facecolor` with an array for each patch,
    # while you can only set `facecolors` with a value for all.

    if h is None:
        h = w

    zipped = np.broadcast(x, y, w, h, rot)
    patches = [
        Ellipse((x_, y_), w_, h_, rot_) for x_, y_, w_, h_, rot_ in zipped
    ]
    collection = PatchCollection(patches, **kwargs)
    if c is not None:
        c = np.broadcast_to(c, zipped.shape).ravel()
        collection.set_array(c)
        collection.set_clim(vmin, vmax)

    ax = plt.gca()
    ax.add_collection(collection)
    ax.autoscale_view()
    plt.draw_if_interactive()
    if c is not None:
        plt.sci(collection)
    return collection


def lighten_color(color, amount=0.5):
    """
    Lightens the given color by multiplying (1-luminosity) by the given amount.
    Input can be matplotlib color string, hex string, or RGB tuple.

    Examples:
    >> lighten_color('g', 0.3)
    >> lighten_color('#F034A3', 0.6)
    >> lighten_color((.3,.55,.1), 0.5)
    """
    import matplotlib.colors as mc
    import colorsys
    try:
        c = mc.cnames[color]
    except:
        c = color
    c = colorsys.rgb_to_hls(*mc.to_rgb(c))
    return colorsys.hls_to_rgb(c[0], 1 - amount * (1 - c[1]), c[2])


def plot(histos):
    H, W = 25, 20
    fig, ax = plt.subplots(1, 1, figsize=(H, W), sharex=False, sharey=False)

    set_labels(fig, "Operation", "Operation duration (sec)")

    min_y = min([
        min([bins[0, :].min() for bins in histo.values()]) for histo in histos
    ]) / 10
    max_y = max([
        max([bins[0, :].max() for bins in histo.values()]) for histo in histos
    ]) * 10

    ax.set_ylim(min_y, max_y)
    ax.set_xlim(0 - 1, 5 * len(histos) + 1)

    ax_ = ax.twinx()
    ax.set_yscale("log")

    ax_.set_ylim(0, 1)
    plt.sca(ax_)  #set current axis

    labels = []
    for i, histo in enumerate(histos):
        for j, (fname, bins) in enumerate(histo.items()):
            centers = bins[0, :]
            counts = bins[1, :]
            radii = (counts * centers) / sum(
                counts *
                centers) / 3 if args.ratio else np.sqrt(np.sqrt(
                    (counts))) / 500

            centers_logscale = (np.log(centers) - np.log(min_y)) / (
                np.log(max_y) - np.log(min_y)
            )  # plot on [0,1] linearly as if it was on [10^min_y, 10^max_y] logly
            xscale = (lambda x: x[1] - x[0])(ax.get_xlim()) * W / H
            ellipses(5 * i + j,
                     centers_logscale,
                     radii * xscale,
                     radii,
                     color=cmap(j),
                     alpha=0.4,
                     ec=lighten_color(cmap(j), amount=1.5),
                     label=fname)
            if i == 0:
                labels.append(fname)

    ax_.legend(handles=get_handles(labels))

    ax_.set_xticks([])
    ax_.set_yticks([])


if __name__ == "__main__":
    paths = find_dirs(args.path, rec=args.R)
    if not paths:
        print("No histo file found")
    else:
        root = os.path.dirname(args.path)
        data = read_histo(paths)
        plot(data)
        plt.savefig(os.path.join(root, 'histo.png'), dpi=300)
