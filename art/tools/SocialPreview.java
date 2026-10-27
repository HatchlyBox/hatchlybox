// SocialPreview.java <out.png>: the 1280x640 picture GitHub shows when a link to Hatchlybox is shared (the repository's
// Settings > Social preview). The mark is drawn from the logo's own shapes (512 units, see docs/logo.svg).
import java.awt.*;
import java.awt.geom.*;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

public class SocialPreview {
    static final Color NAVY = new Color(0x101828), MINT = new Color(0x56DCC9), WHITE = new Color(0xF8FAFC), GREY = new Color(0xA8B3C7);

    public static void main(String[] a) throws Exception {
        int w = 1280, h = 640;
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        g.setColor(NAVY); g.fillRect(0, 0, w, h);
        // A soft mint glow behind the mark.
        g.setPaint(new RadialGradientPaint(new Point2D.Float(300, 320), 330, new float[]{0f, 1f},
            new Color[]{new Color(0x56, 0xDC, 0xC9, 60), new Color(0x56, 0xDC, 0xC9, 0)}));
        g.fillRect(0, 0, w, h);
        // The mark, 512 units scaled to 420 px, centred at (300, 320).
        AffineTransform t = new AffineTransform();
        double s = 420 / 512.0;
        t.translate(300 - 256 * s, 320 - 256 * s); t.scale(s, s);
        Graphics2D m = (Graphics2D) g.create(); m.transform(t);
        m.setColor(WHITE);
        m.fill(new RoundRectangle2D.Double(131, 144, 82, 224, 24, 24));
        m.fill(new RoundRectangle2D.Double(299, 144, 82, 224, 24, 24));
        Path2D bar = new Path2D.Double();
        bar.moveTo(265.70, 278); bar.lineTo(299, 278); bar.lineTo(299, 230.43); bar.closePath();
        m.fill(bar);
        m.setColor(MINT);
        Path2D fold = new Path2D.Double();
        fold.moveTo(212, 229); fold.lineTo(266, 229); fold.lineTo(231, 279); fold.lineTo(212, 279); fold.closePath();
        m.fill(fold);
        m.dispose();
        // The words.
        int x = 560;
        g.setColor(WHITE); g.setFont(new Font("DejaVu Sans", Font.BOLD, 92)); g.drawString("Hatchlybox", x, 270);
        g.setColor(MINT); g.setFont(new Font("DejaVu Sans", Font.BOLD, 46)); g.drawString("Say it. Hatch it.", x, 345);
        g.setColor(GREY); g.setFont(new Font("DejaVu Sans", Font.PLAIN, 28));
        g.drawString("Describe an app or a game. AI builds it,", x, 412);
        g.drawString("installs it and keeps it in one library", x, 452);
        g.drawString("across all your devices.", x, 492);
        g.setColor(WHITE); g.setFont(new Font("DejaVu Sans", Font.PLAIN, 24));
        g.drawString("Linux  ·  macOS  ·  Windows  ·  Android", x, 560);
        g.dispose();
        ImageIO.write(img, "png", new File(a[0]));
    }
}
