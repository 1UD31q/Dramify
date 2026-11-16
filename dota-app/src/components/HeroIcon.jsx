export default function HeroIcon({ hero, size = 'md' }) {
  if (!hero) return <div className={`hero-icon ${size} placeholder`} />;
  return <img className={`hero-icon ${size}`} src={hero.img} alt="" title={hero.name} />;
}
