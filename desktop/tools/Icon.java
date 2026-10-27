// Icon: desktop/icon.png (512 px, for Linux menus and Hatchlybox.app) and desktop/icon.ico (256 px PNG inside, for
// Windows shortcuts), drawn from the brand's app icon (art-src/brand/hatchlybox-app-icon.svg): the white H with
// its see-through diagonal cut and the mint fold, on a navy rounded square.  java Icon.java <desktop dir>
import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.io.*;
import java.nio.file.*;
import javax.imageio.ImageIO;

public class Icon {
    static BufferedImage draw(int size) {
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g.scale(size / 512.0, size / 512.0);
        g.setColor(new Color(0x101828));
        g.fill(new RoundRectangle2D.Double(16, 16, 480, 480, 224, 224));
        Area h = new Area(new RoundRectangle2D.Double(131, 144, 82, 224, 24, 24));
        h.add(new Area(new RoundRectangle2D.Double(299, 144, 82, 224, 24, 24)));
        h.add(new Area(new Rectangle2D.Double(201, 230, 111, 48)));
        h.subtract(new Area(poly(266, 229, 300, 229, 265, 279, 231, 279)));
        g.setColor(new Color(0xF8FAFC));
        g.fill(h);
        g.setColor(new Color(0x56DCC9));
        g.fill(poly(212, 229, 266, 229, 231, 279, 212, 279));
        g.dispose();
        return img;
    }

    static Path2D poly(double... p) {
        Path2D.Double s = new Path2D.Double();
        s.moveTo(p[0], p[1]);
        for (int i = 2; i < p.length; i += 2) s.lineTo(p[i], p[i + 1]);
        s.closePath();
        return s;
    }

    public static void main(String[] a) throws Exception {
        Path dir = Paths.get(a[0]);
        ImageIO.write(draw(512), "png", dir.resolve("icon.png").toFile());
        ByteArrayOutputStream png = new ByteArrayOutputStream();
        ImageIO.write(draw(256), "png", png);
        byte[] b = png.toByteArray();
        // An .ico with one 256 px PNG image (Windows Vista and later read PNG inside .ico).
        ByteArrayOutputStream ico = new ByteArrayOutputStream();
        DataOutputStream o = new DataOutputStream(ico);
        o.write(new byte[] {0, 0, 1, 0, 1, 0});
        o.write(new byte[] {0, 0, 0, 0, 1, 0, 32, 0});
        o.writeInt(Integer.reverseBytes(b.length));
        o.writeInt(Integer.reverseBytes(22));
        o.write(b);
        Files.write(dir.resolve("icon.ico"), ico.toByteArray());
    }
}
